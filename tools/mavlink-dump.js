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
  constructor(systemId = 255, componentId = 190) {
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
    let { uart } = this;
    const clazz = REGISTRY[message.header.msgid]
    if (clazz) {
      let ts = (new Date()).toISOString().substring(11);
      let { MSG_ID, MAGIC_NUMBER } = clazz;
      MSG_ID = MSG_ID.toString(16).toUpperCase().padStart(4, ' ');
      MAGIC_NUMBER = MAGIC_NUMBER.toString(16).toUpperCase().padStart(4, ' ');
      const data = message.protocol.data(message.payload, clazz);
      let tokens = [
        ts.gray,
        uart.blue,
        direction,
        clazz.MSG_NAME.padStart(22).yellow,
        `[${MSG_ID.cyan}]`,
        JSON.stringify(data, (key, value) => typeof value === "bigint" ? Number(value) : value)[color],
      ];
      console.log(tokens.join(' '));
    }
  }

  on_tx_message(message) {
    this.dump_message(message, '<-', 'red');
  }

  on_rx_message(message) {
    this.dump_message(message, '->');
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
  .help()
  .parse(process.argv.slice(2));

const dumper = new MavLinkDumper();

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
