require! <[lodash]>

const PACKET_DELIMITER = '\t'

const PREFIX_LOGGING = '#'
const PREFIX_META_OUT = '!'
const PREFIX_DATA_OUT = '~'
const PREFIX_DATA_IN = '~'
const PREFIX_EVT_OUT = '%'
const PREFIX_FUNC_RSP = '$'

const PACKET_LOG_LEVEL_DEBUG = 'D'
const PACKET_LOG_LEVEL_INFO  = 'I'
const PACKET_LOG_LEVEL_WARN  = 'W'
const PACKET_LOG_LEVEL_ERROR = 'E'


class Parser
  (@parent, @name, pino) ->
    @logger = pino.child {category: 'CmdParser'}
    return

  parse_line: (data) ->
    {logger, name} = self = @
    return console.log "" if data.length is 0
    xs = [ x for x in data ]
    xs.shift! if xs[0] is 0
    return console.log "" if xs.length is 0
    buffer = Buffer.from xs
    hexes = buffer.toString 'hex'
    line = buffer.toString!
    xs = line.split PACKET_DELIMITER
    [prefix, index, category, sub_category, ...payloads] = xs
    return self.process_debug_packet index, category, sub_category, payloads if prefix == PREFIX_LOGGING
    return logger.info "#{name}/stdout: #{line.gray}, `#{prefix}`, #{line.length} bytes"

  process_debug_packet: (index, level, fileline, payloads) ->
    {logger, name} = self = @
    [source, line] = fileline.split '#'
    source = lodash.padStart source, 10, ' '
    line = lodash.padEnd line, 4, ' '
    text = payloads.join PACKET_DELIMITER
    return logger.debug "#{name}<#{source}##{line}>: #{text.gray}"   if level is PACKET_LOG_LEVEL_DEBUG
    return logger.info " #{name}<#{source}##{line}>: #{text.green}"  if level is PACKET_LOG_LEVEL_INFO
    return logger.warn " #{name}<#{source}##{line}>: #{text.yellow}" if level is PACKET_LOG_LEVEL_WARN
    return logger.error "#{name}<#{source}##{line}>: #{text.red}"    if level is PACKET_LOG_LEVEL_ERROR
    return logger.info " #{name}<#{source}##{line}>: #{text.green} (unknown level = #{level.red})"


class Generator
  (@parent, @name, pino) ->
    @logger = pino.child {category: 'CmdParser'}
    @index = 0
    return
  
  gen_data_packet: (chunk, channel) ->
    {logger, name, index} = self = @
    self.index = index + 1
    hexes = chunk.toString 'hex'
    hexes = hexes.toUpperCase!
    xs = [PREFIX_DATA_IN, index.toString!, channel, "livescript", hexes]
    xs = xs.join PACKET_DELIMITER
    return "#{xs}\n"


module.exports = exports = {Parser, Generator}
