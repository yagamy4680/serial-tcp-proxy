SerialPort = require \serialport
SerialServer = require \../helpers/serial
TcpServer = require \../helpers/tcp
WebServer = require \../helpers/web
require! <[pino path]>


ERR_EXIT = (logger, err) ->
  logger.error err
  return process.exit 1


module.exports = exports =
  command: "start <filepath> [<assetDir>]"
  describe: "startup a tcp proxy server on the serial port with specified path"

  builder: (yargs) ->
    yargs
      .example '$0 start /dev/tty.usbmodem1462103', 'run tcp proxy server at default port 8080, and relay the traffic of serial port at path /dev/tty.usbmodem1462103'
      .alias \p, \port
      .default \p, 8080
      .describe \p, "the port number for tcp proxy server to listen"
      .alias \b, \baud
      .default \b, 9600
      .describe \b, "baud rate for opening serial port"
      .alias \d, \databits
      .default \d, 8
      .describe \d, "data bits"
      .alias \y, \parity
      .default \y, \none
      .describe \y, "parity"
      .alias \s, \stopbits
      .default \s, 1
      .describe \s, "stop bits"
      .alias \v, \verbose
      .default \v, no
      .describe \v, "verbose output"
      .boolean 'v'
      .alias \r, \raw
      .default \r, no
      .describe \r, "raw mode, no byline parsing"
      .alias \q, \queued
      .default \q, no
      .describe \q, "buffered data, only for raw mode"
      .boolean <[r q]>
      .demand <[p b d y s v r]>


  handler: (argv) ->
    {config} = global
    {uart, parity, filepath, verbose, raw, queued} = argv
    baudRate = argv.baud
    dataBits = argv.databits
    stopBits = argv.stopbits
    console.log "verbose = #{verbose}"
    console.log "raw = #{raw}"
    console.log "queued = #{queued}"
    opts = {baudRate, dataBits, parity, stopBits}
    level = if verbose then 'trace' else 'info'
    prettyPrint = translateTime: 'SYS:HH:MM:ss.l', ignore: 'pid,hostname'
    console.log "prettyPrint => #{JSON.stringify prettyPrint}"
    logger = pino {prettyPrint, level}
    (ports) <- SerialPort.list! .then
    xs = [ x for x in ports when x.path is filepath ]
    return logger.error "no such port: #{filepath}" unless xs.length >= 1
    xs = xs.pop!
    logger.debug "found #{filepath.yellow} => #{JSON.stringify xs}"
    ss = new SerialServer logger, filepath, baudRate, parity, stopBits, dataBits, raw, queued
    (serr) <- ss.start
    return ERR_EXIT logger, terr if terr?
    ts = new TcpServer logger, argv.port
    (terr) <- ts.start
    return ERR_EXIT logger, terr if terr?
    ws = new WebServer logger, argv.port + 1, argv.assetDir, filepath, opts
    (werr) <- ws.start
    return ERR_EXIT logger, werr if werr?

    ss.on \bytes, (chunk) -> 
      DBG = if raw then logger.info else logger.debug
      DBG.apply logger, ["receive #{chunk.length} bytes from serial (#{(chunk.toString 'hex').toUpperCase!})"]
      ts.broadcast chunk
      ws.broadcast chunk

    filename = path.basename filepath
    filename = filename.substring 4 if filename.startsWith "tty."

    ss.on \line, (line) -> logger.info "#{filename.yellow}: #{line}"

    ts.on \data, (chunk, connection) ->
      logger.info "receive #{chunk.length} bytes from tcp (#{(chunk.toString 'hex').toUpperCase!})"
      ss.write chunk
