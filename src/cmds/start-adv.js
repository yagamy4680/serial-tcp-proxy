const SerialPort = require('serialport');
const SerialServer = require('../helpers/serial-adv');
const TcpServer = require('../helpers/tcp');
const WebServer = require('../helpers/web');
const pino = require('pino');
const pretty = require('pino-pretty');
const fs = require('fs');
const path = require('path');

function ERR_EXIT(logger, err) {
  logger.error(err);
  console.dir(err);
  return process.exit(1);
}

async function start_service_async(service) {
  return new Promise((resolve, reject) => {
    service.start((err) => {
      if (err) return reject(err);
      resolve();
    });
  });
}


module.exports = {
  command: 'start-adv <filepath> [<assetDir>]',
  describe: 'startup a tcp proxy server on the serial port with specified path, and/or follow',

  builder: (yargs) => {
    return yargs
      .example('$0 start /dev/tty.usbmodem1462103', 'run tcp proxy server at default port 8080, and relay the traffic of serial port at path /dev/tty.usbmodem1462103')
      .alias('p', 'port').default('p', 8080).describe('p', 'the port number for tcp proxy server to listen')
      .alias('b', 'baud').default('b', 9600).describe('b', 'baud rate for opening serial port')
      .alias('d', 'databits').default('d', 8).describe('d', 'data bits')
      .alias('y', 'parity').default('y', 'none').describe('y', 'parity')
      .alias('s', 'stopbits').default('s', 1).describe('s', 'stop bits')
      .alias('v', 'verbose').default('v', false).describe('v', 'verbose output')
      .alias('q', 'queued').default('q', 0).describe('q', 'buffered data for X milliseconds before emitting. 0 indicates to disable this feature, and mimimal value for X is 5ms')
      .alias('c', 'capture').default('c', 'none').describe('c', 'enable capture mode to record serial transmission data, might be none, serial, tcp, or both')
      .alias('f', 'follow').default('f', false).describe('f', 'follow the serial port, i.e. restart the server when the serial port is re-connected')
      .boolean(['v', 'f'])
      .demandOption(['p', 'b', 'd', 'y', 's', 'v', 'q']);
  },

  handler: async (argv) => {
    const { config } = global;
    let { uart, parity, filepath, verbose, raw, capture, follow, queued } = argv;
    const baudRate = argv.baud;
    const dataBits = argv.databits;
    const stopBits = argv.stopbits;

    console.log(`verbose = ${verbose}`);
    console.log(`raw = ${raw}`);
    console.log(`queued = ${queued} (${typeof queued})`);
    console.log(`capture = ${capture}`);

    const level = verbose ? 'debug' : 'info';
    const messageFormat = (log, messageKey) => {
      const { category } = log;
      const message = log[messageKey];
      if (category) return `${category}: ${message}`;
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
    const options = { baudRate, parity, stopBits, dataBits, queued, capture, verbose, follow };
    const ss = new SerialServer(logger, filepath, options);
    try {
      await ss.start();
    } catch (err) {
      return ERR_EXIT(logger, err);
    }

    const ts = new TcpServer(logger, argv.port, queued);
    try {
      await start_service_async(ts);
    } catch (err) {
      return ERR_EXIT(logger, err);
    }

    const ws = new WebServer(logger, argv.port + 1, argv.assetDir, filepath, { baudRate, dataBits, parity, stopBits });
    try {
      await start_service_async(ws);
    } catch (err) {
      return ERR_EXIT(logger, err);
    }

    uart = ss.get_name();

    module.from_serial_bytes = 0;
    module.to_serial_bytes = 0;

    function PRINT(chunk, from_serial = true) {
      // let text = chunk.toString('hex').toUpperCase();
      // const size = String(chunk.length).padStart(3, ' ');
      // const direction = from_serial ? '=>' : '<=';
      // const DBG = raw ? logger.info.bind(logger) : logger.debug.bind(logger);
      // DBG(`${uart} ${direction} ${size} bytes: ${text}`);
    }

    ss.on('bytes', (chunk) => {
      PRINT(chunk, true);
      ts.broadcast(chunk);
      ws.broadcast('from_serial', { chunk: chunk.toString('base64') });
      module.from_serial_bytes += chunk.length;
    });

    ts.on('data', (chunk, connection) => {
      PRINT(chunk, false);
      ss.write(chunk);
      ws.broadcast('to_serial', { chunk: chunk.toString('base64') });
      module.to_serial_bytes += chunk.length;
    });

    const on_timeout = () => {
      const from_serial_bytes = module.from_serial_bytes || 0;
      const to_serial_bytes = module.to_serial_bytes || 0;
      if (argv.metric) {
        logger.info(`${uart} total: ${from_serial_bytes} bytes from serial, ${to_serial_bytes} bytes to serial`);
      }
      ws.broadcast('status', { from_serial_bytes, to_serial_bytes, uart });
      module.from_serial_bytes = 0;
      module.to_serial_bytes = 0;
    };

    setInterval(on_timeout, 1000);
  }
};
