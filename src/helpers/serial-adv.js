const fs = require('fs').promises;
const path = require('path');
const { EventEmitter } = require('events');
const { SerialPort } = require('serialport');
const Recorder = require('./recorder');


const DEFAULT_OPTIONS = {
  baudRate: 9600,
  parity: 'none',
  stopBits: 1,
  dataBits: 8,
  queued: 0,
  capture: false,
  verbose: false,
  follow: false,
};

const CHECK_SERIAL_PORT_INTERVAL = 3; // seconds


module.exports = class SerialServer extends EventEmitter {
  constructor(pino, filepath, options) {
    super();
    this.filepath = filepath;
    this.options = Object.assign({}, DEFAULT_OPTIONS, options);
    const { capture, queued, verbose, follow } = this.options;
    this.verbose = verbose;
    this.follow = follow;

    this.port = null;
    this.connected = false;

    this.data_buffer = [];
    this.logger = pino.child({ category: 'SerialServer' });
    this.recorder = new Recorder(this, this.logger, capture);

    this.queued = queued > 0;
    this.queued_interval = queued;
    if (this.queued) {
      const f = () => this.at_timer_expiry();
      this.logger.info(`queued = ${this.queued_interval}ms`);
      this.queued_timer = setInterval(f, this.queued_interval);
    }

    this.check_timer = null;
    this.serial_realpath = null;
    this.serial_name = null;

    this.metric_timer = null;
    this.from_serial_bytes = 0;
    this.to_serial_bytes = 0;
  }

  get_name() {
    let name = this.serial_name || this.filepath;
    if (name.startsWith('tty.')) name = name.substring(4);
    return name;
  }

  print_chunk(chunk, from_serial = true, warning = false) {
    let { logger, serial_name, verbose } = this;
    if (!verbose) return;
    let text = chunk.toString('hex').toUpperCase();
    const size = String(chunk.length).padStart(3, ' ');
    const direction = from_serial ? '=>' : '<=';
    text = warning ? text.gray : (from_serial ? text.blue : text.magenta);
    logger.info(`${serial_name.yellow} ${direction} ${size} bytes: ${text}`);
  }

  emit_bytes_internally(chunk) {
    const { recorder } = this;
    try {
      this.emit('bytes', chunk);    
    } catch (error) {
      // do nothing
    }
    recorder.save_data_from_serial(chunk);
    this.print_chunk(chunk, true);
  }

  at_timer_expiry() {
    const { data_buffer, queued, verbose } = this;
    if (!queued) return;
    if (data_buffer.length === 0) return;
    // preserve the buffered bytes, then reset the buffer
    const oldBuffer = data_buffer;
    this.data_buffer = [];
    const chunk = Buffer.from(oldBuffer);
    if (verbose) this.logger.debug(`emit queued data (${chunk.toString('hex').toUpperCase()}), ${oldBuffer.length} bytes`);
    return this.emit_bytes_internally(chunk);
  }

  emit_bytes(chunk, immediate = true) {
    const { logger, data_buffer, queued, verbose } = this;
    this.from_serial_bytes += chunk.length;
    if (immediate) return this.emit_bytes_internally(chunk);
    if (!queued) return this.emit_bytes_internally(chunk);
    if (verbose) logger.debug(`receive ${chunk.length} bytes from serial (${chunk.toString('hex').toUpperCase()}) but queued`);
    const xs = Array.from(chunk);
    this.data_buffer = data_buffer.concat(xs);
  }

  write(chunk) {
    const { recorder, port, connected } = this;
    this.to_serial_bytes += chunk.length;
    this.print_chunk(chunk, false, !connected);
    recorder.save_data_from_tcp(chunk);
    if (!connected) return;
    return port.write(chunk);
  }

  on_error(err) {
    const { logger, filepath } = this;
    console.log(`${filepath}: err => ${err}`);
    logger.error(err);
    this.emit('error', err);
    this.connected = false;
  }

  on_close() {
    const { logger, filepath } = this;
    logger.error(`${filepath}: port is closed!!`);
    this.emit('close', {});
    this.connected = false;
  }

  async on_check_serial_port() {
    if (this.connected) return;
    if (this.follow) await this.detect_serial_port();
  }

  async on_metric_timeout() {
    let { logger, verbose, from_serial_bytes, to_serial_bytes } = this;
    this.from_serial_bytes = 0;
    this.to_serial_bytes = 0;
    if (!verbose) {
      logger.info(`${this.get_name().yellow} throughputs: ${from_serial_bytes.toString().padStart(5, ' ').blue} / ${to_serial_bytes.toString().padEnd(5, ' ').magenta} from/to serial (bytes/sec)`);
    }
  }

  async start_raw_mode() {
    const { baudRate, parity, stopBits, dataBits } = this.options;
    const autoOpen = false;
    const opts = { autoOpen, baudRate, dataBits, parity, stopBits, path: this.serial_realpath };
    let port = this.port = new SerialPort(opts);
    port.on('error', (err) => this.on_error(err));
    port.on('close', () => this.on_close());

    if (this.connected) return Promise.resolve();
    this.logger.info(`opening ${this.filepath} with options: ${JSON.stringify(opts)} in RAW mode ...`);
    return new Promise((resolve, reject) => {
      port.open((err) => {
        if (err) return reject(err);
        this.connected = true;
        if (this.verbose) this.logger.debug('opened');
        port.on('data', (chunk) => this.emit_bytes(chunk, false));
        resolve();
      });
    });
  }

  async detect_serial_port() {
    let { filepath, logger, follow } = this;
    this.serial_name = path.basename(filepath);
    if (this.serial_name.startsWith('tty.')) this.serial_name = this.serial_name.substring(4);
    try {
      this.serial_realpath = await fs.realpath(filepath);
      this.serial_name = path.basename(this.serial_realpath);
      if (this.serial_name.startsWith('tty.')) this.serial_name = this.serial_name.substring(4);
    } catch (err) {
      return this.err_exit(err, `${filepath}: failed to resolve real path`);
    }
    logger.info(`detected symbolic link, resolve ${filepath} as ${this.serial_realpath}`);

    let ports;
    try {
      ports = await SerialPort.list();
    } catch (err) {
      return this.err_exit(err, `failed to list serial ports`);
    }

    let xs = ports.filter(x => x.path === this.serial_realpath);
    if (xs.length < 1) {
      return this.err_exit(new Error(`no such port`), `${this.serial_realpath}: no such port`);
    }
    const xsItem = xs.pop();
    logger.debug(`found ${this.serial_realpath} => ${JSON.stringify(xsItem)}`);

    if (follow && !this.connected) {
      await this.start_raw_mode();
    }
  }

  async start() {
    let { recorder } = this;
    recorder.start();
    await this.detect_serial_port();
    this.check_timer = setInterval(async () => await this.on_check_serial_port(), CHECK_SERIAL_PORT_INTERVAL * 1000);
    this.metric_timer = setInterval(async () => await this.on_metric_timeout(), 1000);
  }

  err_exit(err, message) {
    let { logger, follow } = this;
    if (follow) {
      logger.error(`${message} (${err.message.red})`);
    }
    else {
      logger.error(message);
      console.dir(err);
      process.exit(1);
    }
  }

};
