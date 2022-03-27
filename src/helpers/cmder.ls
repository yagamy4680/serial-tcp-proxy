EventEmitter = require \events
require! <[lodash]>

const PACKET_DELIMITER = '\t'
const PACKET_TERMINATOR = '\n'

const PREFIX_LOGGING = '#'
const PREFIX_META_OUT = '!'
const PREFIX_DATA_OUT = '~'
const PREFIX_DATA_IN = '~'
const PREFIX_EVT_OUT = '%'
const PREFIX_EVT_IN = '%'
const PREFIX_FUNC_RSP = '$'

const PACKET_LOG_LEVEL_DEBUG = 'D'
const PACKET_LOG_LEVEL_INFO  = 'I'
const PACKET_LOG_LEVEL_WARN  = 'W'
const PACKET_LOG_LEVEL_ERROR = 'E'

const PACKET_META_GROUP_PREBUILT_PROPERTY = 'P'
const PACKET_META_GROUP_TIMER = 'T'


class Parser extends EventEmitter
  (@parent, @name, pino) ->
    @logger = pino.child {group: 'CmdParser'}
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
    [prefix, index, group, key, ...payloads] = xs
    index = parseInt index
    return self.process_debug_packet index, group, key, payloads if prefix == PREFIX_LOGGING
    return self.process_metadata_packet index, group, key, payloads if prefix == PREFIX_META_OUT
    return self.process_event_packet index, group, key, payloads if prefix == PREFIX_EVT_OUT
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

  process_metadata_packet: (index, group, key, payloads) ->
    {logger, name} = self = @
    if PACKET_META_GROUP_TIMER == group
      self.emit 'timer-req', key, parseInt(payloads[0])
    else
      key = lodash.padEnd key, 16, ' '
      return logger.info "#{name}:#{group.magenta}[#{key.white}] = #{payloads[0].yellow}"

  process_event_packet: (index, group, key, payloads) ->
    {logger, name} = self = @
    try
      json = JSON.parse payloads[0]
    catch
      return logger.info "#{name}:EVT:[#{group.white}.#{key.white}] => (invalid json) => #{payloads[0].red}"
    return logger.info "#{name}:EVT:[#{group.white}.#{key.white}] => #{JSON.stringify json}"


class Generator
  (@parent, @name, pino) ->
    @logger = pino.child {group: 'CmdParser'}
    @index = 0
    return

  to_buffer: (tokens) ->
    xs = tokens.join PACKET_DELIMITER
    return Buffer.from "#{xs}#{PACKET_TERMINATOR}"
  
  gen_data_packet: (chunk, channel) ->
    {logger, name, index} = self = @
    self.index = index + 1
    hexes = chunk.toString 'hex'
    hexes = hexes.toUpperCase!
    xs = [PREFIX_DATA_IN, index.toString!, channel, "livescript", hexes]
    xs = self.to_buffer xs
    return xs

  gen_event_packet: (group, evt, text) ->
    {logger, name, index} = self = @
    self.index = index + 1
    xs = [PREFIX_EVT_IN, index.toString!, group, evt, text]
    xs = self.to_buffer xs
    return xs



module.exports = exports = {Parser, Generator}
