const { SerialPort } = require('serialport');
const WebServer = require('../helpers/web');
const pino = require('pino');
const path = require('path');
const fs = require('fs');
const lodash = require('lodash');
const pretty = require('pino-pretty');
const { spawn } = require('child_process');

function ERR_EXIT(logger, err) {
  logger.error(err);
  return process.exit(1);
}

class ExecutableProcess {
  constructor(fullpath, logger) {
    this.fullpath = fullpath;
    this.logger = logger;
    if (!fullpath) return;
    const name = path.basename(fullpath);
    const child = spawn(fullpath);
    this.name = name;
    this.child = child;
    this.stdout = byline(child.stdout);
    this.stdout.on('data', (line) => logger.info(`${name}/stdout: ${line}`));
    this.stderr = byline(child.stderr);
    this.stderr.on('data', (line) => logger.info(`${name}/stderr: ${line}`));
    this.stdin = child.stdin;
    child.on('exit', () => process.exit(0));
  }

  feed(chunk) {
    if (this.stdin) this.stdin.write(chunk);
  }
}

module.exports = {
  command: 'start-bridge <serial1> <serial2>',
  describe: 'bridge the 2 given serial ports, and start a websocket server to expose the serial port data',

  builder: (yargs) => {
    return yargs
      .example('$0 start-bridge /dev/tty.usbmodem1462103:115200 /dev/tty.usbserial-AQ015JZC', 'bridge the two serial ports and start a websocket server')
      .alias('p', 'port')
      .default('p', 8080)
      .describe('p', 'the port number for tcp proxy server to listen')
      .alias('v', 'verbose')
      .default('v', false)
      .describe('v', 'verbose output')
      .boolean('v')
      .boolean(['v'])
      .demandOption(['p']);
  },

  handler: async (argv) => {
    const { config } = global;
    let { port, verbose, serial1, serial2 } = argv;

    const level = verbose ? 'debug' : 'info';
    const messageFormat = (log, messageKey) => {
      const { category } = log || {};
      const message = log[messageKey];
      if (category) return `${category.gray}: ${message}`;
      return message;
    };
    const transport = pretty({
      translateTime: 'SYS:HH:MM:ss.l',
      ignore: 'pid,hostname',
      sync: true,
      hideObject: true,
      messageFormat
    });
    const logger = pino({ level }, transport);

    let [serial1_path, serial1_baudrate] = serial1.split(':');
    serial1_baudrate = serial1_baudrate ? (parseInt(serial1_baudrate) || 115200) : 115200;

    let [serial2_path, serial2_baudrate] = serial2.split(':');
    serial2_baudrate = serial2_baudrate ? (parseInt(serial2_baudrate) || 115200) : 115200;

    let serial1_realpath = null;
    let serial2_realpath = null;
    try {
      serial1_realpath = fs.realpathSync(serial1_path);
    } catch (ferr) {
      console.dir(ferr, `failed to resolve ${serial1_path}`);
      return;
    }
    try {
      serial2_realpath = fs.realpathSync(serial2_path);
    } catch (ferr) {
      console.dir(ferr, `failed to resolve ${serial2_path}`);
      return;
    }

    let ports;
    try {
      ports = await SerialPort.list();
    } catch (err) {
      return ERR_EXIT(logger, err);
    }

    let xs = ports.filter(x => x.path === serial1_realpath);
    if (xs.length < 1) {
      logger.error(`no such port: ${serial1_realpath}`);
      return;
    }
    else {
      serial1_realpath = xs.pop().path;
    }
    xs = ports.filter(x => x.path === serial2_realpath);
    if (xs.length < 1) {
      logger.error(`no such port: ${serial2_realpath}`);
      return;
    }
    else {
      serial2_realpath = xs.pop().path;
    }
    logger.info(`bridging ${serial1_realpath} <=> ${serial2_realpath}`);

    let serial1_name = path.basename(serial1_realpath);
    if (serial1_name.startsWith('tty.')) serial1_name = serial1_name.substring(4);
    let serial2_name = path.basename(serial2_realpath);
    if (serial2_name.startsWith('tty.')) serial2_name = serial2_name.substring(4);

    const sp1 = new SerialPort({ path: serial1_realpath, baudRate: serial1_baudrate, autoOpen: false });
    const sp2 = new SerialPort({ path: serial2_realpath, baudRate: serial2_baudrate, autoOpen: false });
    sp1.on('error', (err) => ERR_EXIT(logger, err));
    sp2.on('error', (err) => ERR_EXIT(logger, err));
    sp1.on('close', () => {
      logger.info(`${serial1_realpath} closed`);
      process.exit(0);
    });
    sp2.on('close', () => {
      logger.info(`${serial2_realpath} closed`);
      process.exit(0);
    });

    sp1.open((err) => {
      if (err) {
        return ERR_EXIT(logger, err);
      }
      logger.info(`${serial1_realpath} opened at ${serial1_baudrate} baudrate`);
    });

    sp2.open((err) => {
      if (err) {
        return ERR_EXIT(logger, err);
      }
      logger.info(`${serial2_realpath} opened at ${serial2_baudrate} baudrate`);
    });

    const ws = new WebServer(logger, argv.port, argv.assetDir, serial1_name, { baudRate: 115200 });
    ws.start(async () => {

      const counters = { from_serial_bytes: 0, to_serial_bytes: 0 };

      function PRINT(chunk, from_serial1 = true) {
        let text = chunk.toString('hex').toUpperCase();
        const size = lodash.padStart(String(chunk.length), 3, ' ');
        const direction = from_serial1 ? '=>' : '<=';
        logger.info(`${serial1_name} ${direction} ${serial2_name}, ${size} bytes: ${text}`);
      }

      sp1.on('data', (chunk) => {
        sp2.write(chunk);
        PRINT(chunk, true);
        ws.broadcast('from_serial', { chunk: chunk.toString('base64') });
        counters.from_serial_bytes += chunk.length;
      });

      sp2.on('data', (chunk) => {
        sp1.write(chunk);
        PRINT(chunk, false);
        ws.broadcast('to_serial', { chunk: chunk.toString('base64') });
        counters.to_serial_bytes += chunk.length;
      });

      const on_timeout = () => {
        const { from_serial_bytes, to_serial_bytes } = counters;
        // logger.info(`${serial1_name}<=>${serial2_name}, total: ${from_serial_bytes} bytes from serial, ${to_serial_bytes} bytes to serial`);
        ws.broadcast('status', { from_serial_bytes, to_serial_bytes, serial1: serial1_name, serial2: serial2_name, uart: serial1_name });
        counters.from_serial_bytes = 0;
        counters.to_serial_bytes = 0;
      };

      setInterval(on_timeout, 1000);
    });

  }
};
