require! <[pino path net]>
pretty = require \pino-pretty
{Executer} = require \../helpers/executer


ERR_EXIT = (logger, err) ->
  logger.error err
  return process.exit 1


module.exports = exports =
  command: "tcp-executer <executable>"
  describe: "start a tcp client to a running serial-tcp-proxy to fetch serial data, and feed to <executable> for processing"

  builder: (yargs) ->
    yargs
      .alias \p, \port
      .default \p, 8080
      .describe \p, "the TCP port number that serial-tcp-proxy is listening"
      .alias \s, \server
      .default \s, \127.0.0.1
      .describe \s, "the server address that serial-tcp-proxy is listening"
      .alias \v, \verbose
      .default \v, no
      .describe \v, "verbose output"
      .boolean <[v]>
      .demand <[p s]>


  handler: (argv) ->
    {config} = global
    {port, server, verbose, executable, _} = argv
    console.log "verbose = #{verbose}"
    console.log "port = #{port}"
    console.log "server = #{server}"
    console.log "current = #{__dirname}"
    console.log "process.cwd = #{process.cwd!}"
    executable = path.resolve "#{process.cwd!}/#{executable}"
    console.log "executable = #{executable}"
    console.log "executable arguments = #{JSON.stringify argv._}"

    level = if verbose then 'debug' else 'info'
    options = translateTime: 'SYS:HH:MM:ss.l', ignore: 'pid,hostname'
    messageFormat = (log, messageKey) ->
      {category} = log
      message = log[messageKey]
      return "#{category.gray}: #{message}" if category?
      return message
    transport = pretty translateTime: 'SYS:HH:MM:ss.l', ignore: 'pid,hostname', sync: yes, hideObject: yes, messageFormat: messageFormat
    logger = pino {level}, transport

    args = argv._
    args.shift!
    exe = new Executer null, logger, executable, args

    tcp = new net.Socket!

    tcp.on \error, (err) -> logger.error err

    tcp.on \data, (data) -> exe.feed data, "src2dst"

    tcp.connect port, server, -> logger.info "connected."
