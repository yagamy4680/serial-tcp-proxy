SerialPort = require \serialport
SerialServer = require \../helpers/serial
TcpServer = require \../helpers/tcp
WebServer = require \../helpers/web
require! <[pino path fs lodash]>
pretty = require \pino-pretty

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
      .alias \c, \capture
      .default \c, "none"
      .describe \c, "enable catprue mode to record serial transmission data, might be none, serial, tcp, or both"
      .boolean <[r q]>
      .demand <[p b d y s v r]>


  handler: (argv) ->
    {config} = global
    {uart, parity, filepath, verbose, raw, queued, capture} = argv
    baudRate = argv.baud
    dataBits = argv.databits
    stopBits = argv.stopbits
    console.log "verbose = #{verbose}"
    console.log "raw = #{raw}"
    console.log "queued = #{queued}"
    console.log "capture = #{capture}"

    level = if verbose then 'debug' else 'info'
    options = translateTime: 'SYS:HH:MM:ss.l', ignore: 'pid,hostname'
    messageFormat = (log, messageKey) ->
      {category} = log
      message = log[messageKey]
      return "#{category.gray}: #{message}" if category?
      return message
    transport = pretty translateTime: 'SYS:HH:MM:ss.l', ignore: 'pid,hostname', sync: yes, hideObject: yes, messageFormat: messageFormat
    logger = pino {level}, transport

    (ferr, real_filepath) <- fs.realpath filepath
    return console.dir ferr, "failed to resolve #{filepath}" if ferr?
    logger.info "detected symbolic link, resolve #{filepath.yellow} as #{real_filepath.cyan}"
    (ports) <- SerialPort.list! .then
    xs = [ x for x in ports when x.path is real_filepath ]
    return logger.error "no such port: #{real_filepath}" unless xs.length >= 1
    xs = xs.pop!
    logger.debug "found #{real_filepath.yellow} => #{JSON.stringify xs}"
    ss = new SerialServer logger, real_filepath, baudRate, parity, stopBits, dataBits, raw, queued, capture
    (serr) <- ss.start
    return ERR_EXIT logger, terr if terr?
    ts = new TcpServer logger, argv.port, queued
    (terr) <- ts.start
    return ERR_EXIT logger, terr if terr?
    ws = new WebServer logger, argv.port + 1, argv.assetDir, filepath, {baudRate, dataBits, parity, stopBits}
    (werr) <- ws.start
    return ERR_EXIT logger, werr if werr?

    uart = path.basename real_filepath

    PRINT = (chunk, from_serial=yes) ->
      text = chunk.toString 'hex'
      text = text.toUpperCase!
      text = if from_serial then text.white else text.red
      size = chunk.length
      size = lodash.padStart size.toString!, 3, ' '
      direction = if from_serial then "=>".white else "<=".red
      DBG = if raw then logger.info else logger.debug
      DBG.apply logger, ["#{uart} #{direction} #{size.gray} bytes: #{text}"]

    ss.on \bytes, (chunk) -> 
      PRINT chunk, yes
      ts.broadcast chunk
      ws.broadcast chunk

    filename = path.basename filepath
    filename = filename.substring 4 if filename.startsWith "tty."

    ss.on \line, (line) -> logger.info "#{filename.yellow}: #{line}"

    ss.on \error, (err) -> 
      process.exit 1
    
    ss.on \close, ->
      process.exit 1

    ts.on \data, (chunk, connection) ->
      PRINT chunk, no
      ss.write chunk
