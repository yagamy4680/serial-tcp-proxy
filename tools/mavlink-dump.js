const path = require('path');
const fs = require('fs').promises;
const util = require('util');
const zlib = require('zlib');
const gzip = util.promisify(zlib.gzip);

const colors = require('colors');
const yargs = require('yargs');
const io = require('socket.io-client');
const { MavLinkPacketSplitter, MavLinkPacketParser, MavLinkPacketRegistry, minimal, common, ardupilotmega } = require('node-mavlink');
const { Writable, PassThrough } = require('stream');


/**
 * 1. Connect to WebSocket server as client, with given `host` and `port`. Note, the channel is always `/serial`.
 * 2. Listen to `from_serial`, `to_serial`, and `status` events, and dump them to console.
 * 3. The `host` and `port` are given as command line arguments, parsed by yargs library.
 */

function hexDump(buffer, prefix = null, color = 'white') {
  const bytesPerLine = 16;
  const spaces = prefix ? prefix.length + 4 : 0;
  const space_chars = ' '.repeat(spaces);

  for (let i = 0; i < buffer.length; i += bytesPerLine) {
    const slice = buffer.slice(i, i + bytesPerLine);
    const hex = Array.from(slice)
      .map(b => b.toString(16).padStart(2, '0'))
      .join(' ');
    const ascii = Array.from(slice)
      .map(b => (b >= 32 && b <= 126 ? String.fromCharCode(b) : '.'))
      .join('');
    let ts = (new Date()).toISOString().substring(11);
    let tokens = [];
    if (i === 0) {
      tokens.push(ts.gray);
      if (prefix) {
        tokens.push(prefix.blue);
      }
    }
    else {
      tokens.push(space_chars);
    }
    tokens.push(i.toString(16).padStart(4, '0'));
    tokens.push(' ');
    tokens.push(hex.padEnd(bytesPerLine * 3)[color]);
    tokens.push(ascii.gray);
    let text = tokens.join(' ');
    console.log(text);
  }
}

// create a registry of mappings between a message id and a data class
const REGISTRY = {
  ...minimal.REGISTRY,
  ...common.REGISTRY,
  ...ardupilotmega.REGISTRY,
};

class MavLinkDumper {
  constructor(systemId = 255, componentId = 190, destination_dir = null, quiet = false, interval = 60) {
    this.uart = 'unknown';
    this.tx_splitter = new MavLinkPacketSplitter();
    this.tx_parser = new MavLinkPacketParser();
    this.rx_splitter = new MavLinkPacketSplitter();
    this.rx_parser = new MavLinkPacketParser();
    this.systemId = systemId;
    this.componentId = componentId;
    this.tx_splitter.pipe(this.tx_parser);
    this.rx_splitter.pipe(this.rx_parser);
    this.tx_splitter.on('data', (packet) => this.on_tx_packet(packet));
    this.rx_splitter.on('data', (packet) => this.on_rx_packet(packet));
    this.tx_parser.on('data', (message) => this.on_tx_message(message));
    this.rx_parser.on('data', (message) => this.on_rx_message(message));
    this.lines = [];
    this.quiet = quiet;
    this.destination_dir = destination_dir;
    if (this.destination_dir) {
      this.timer = setInterval(async () => await this.on_timeout(), interval * 1000);
      setImmediate(async () => await fs.mkdir(this.destination_dir, { recursive: true }));
    }
  }

  set_uart(uart) {
    this.uart = uart;
  }

  feed_tx(data) {
    this.tx_splitter.write(data);
  }

  feed_rx(data) {
    this.rx_splitter.write(data);
  }

  on_tx_packet(packet) {

  }

  on_rx_packet(packet) {

  }

  dump_message(message, direction = '->', color = 'white') {
    let { uart, lines } = this;
    const clazz = REGISTRY[message.header.msgid]
    const now = Date.now();
    if (clazz) {
      let ts = (new Date()).toISOString().substring(11);
      let { MSG_ID, MAGIC_NUMBER } = clazz;
      MSG_ID = MSG_ID.toString(16).toUpperCase().padStart(4, ' ');
      MAGIC_NUMBER = MAGIC_NUMBER.toString(16).toUpperCase().padStart(4, ' ');
      const data = message.protocol.data(message.payload, clazz);
      let text = JSON.stringify(data, (key, value) => typeof value === "bigint" ? Number(value) : value);
      let tokens = [
        ts.gray,
        uart.blue,
        direction,
        clazz.MSG_NAME.padStart(22).yellow,
        `[${MSG_ID.cyan}]`,
        text[color],
      ];
      if (this.destination_dir) {
        lines.push([now.toString(), direction, clazz.MSG_NAME, text].join('\t'));
      }
      if (!this.quiet) {
        console.log(tokens.join(' '));
      }
    }
  }

  on_tx_message(message) {
    this.dump_message(message, '<-', 'red');
  }

  on_rx_message(message) {
    this.dump_message(message, '->');
  }

  async on_timeout() {
    let { lines } = this;
    this.lines = [];
    if (lines.length == 0) return;
    const now = (new Date()).toISOString().substring(0, 19).replace('T', ' ');
    const header = ['timestamp', 'direction', 'message'].join('\t');
    lines.unshift(header);
    const text = lines.join('\n');
    const buffer = Buffer.from(text, 'utf-8');
    const compressed = await gzip(buffer);
    const filename = path.join(this.destination_dir, `mavlink-dump-${this.uart}-${now.replace(/[: ]/g, '_')}.tsv.gz`);

    try {
      await fs.writeFile(filename, compressed);
      console.log(`${now}: Dumped ${lines.length} messages to ${filename.green}`);
    }
    catch (err) {
      console.error(`Failed to write to ${filename.red}: ${err.message}`);
    }
  }
}


// Parse command line arguments
const argv = yargs()
  .option('host', {
    alias: 'h',
    describe: 'WebSocket server host',
    demandOption: true,
    type: 'string',
    default: 'localhost'
  })
  .option('port', {
    alias: 'p',
    describe: 'WebSocket server port',
    demandOption: true,
    type: 'number'
  })
  .option('destination_dir', {
    alias: 'd',
    describe: 'Directory to save dump files',
    demandOption: true,
    type: 'string',
    default: null
  })
  .option('quiet', {
    alias: 'q',
    describe: 'Suppress output to console',
    demandOption: false,
    type: 'boolean',
    default: false
  })
  .option('interval', {
    alias: 'i',
    describe: 'Interval between dumps (in seconds)',
    demandOption: false,
    type: 'number',
    default: 60
  })
  .help()
  .parse(process.argv.slice(2));

const dumper = new MavLinkDumper(255, 190, argv.destination_dir, argv.quiet, argv.interval);

// Build WebSocket URL
const url = `ws://${argv.host}:${argv.port}/serial`;

// Connect to WebSocket server
const socket = io(url);

let uart = 'unknown';

// Listen and dump events to console
socket.on('connect', () => {
  console.log(`Connected to ${url}`);
});

socket.on('from_serial', (data) => {
  let { chunk } = data;
  let bytes = Buffer.from(chunk, 'base64');
  dumper.feed_rx(bytes);
});

socket.on('to_serial', (data) => {
  let { chunk } = data;
  let bytes = Buffer.from(chunk, 'base64');
  dumper.feed_tx(bytes);
});

socket.on('status', (data) => {
  // console.log('[status]', data);
  uart = data.uart || uart;
  dumper.set_uart(uart);
});

socket.on('disconnect', () => {
  console.log('Disconnected');
});

socket.on('connect_error', (err) => {
  console.error('Connection error:', err.message);
});
