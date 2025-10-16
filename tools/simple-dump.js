const yargs = require('yargs');
const io = require('socket.io-client');


/**
 * 1. Connect to WebSocket server as client, with given `host` and `port`. Note, the channel is always `/serial`.
 * 2. Listen to `from_serial`, `to_serial`, and `status` events, and dump them to console.
 * 3. The `host` and `port` are given as command line arguments, parsed by yargs library.
 */


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

// Build WebSocket URL
const url = `ws://${argv.host}:${argv.port}/serial`;

// Connect to WebSocket server
const socket = io(url);

// Listen and dump events to console
socket.on('connect', () => {
  console.log(`Connected to ${url}`);
});

socket.on('from_serial', (data) => {
  console.log('[from_serial]', data);
});

socket.on('to_serial', (data) => {
  console.log('[to_serial]', data);
});

socket.on('status', (data) => {
  console.log('[status]', data);
});

socket.on('disconnect', () => {
  console.log('Disconnected');
});

socket.on('connect_error', (err) => {
  console.error('Connection error:', err.message);
});
