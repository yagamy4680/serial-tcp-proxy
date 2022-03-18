#
# Copyright (c) 2019 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
require! <[os lodash fs]>
{StepTimer} = require \./step-timer

const RECORDER_DATA_DIRECTION_FROM_SERIAL = '<='
const RECORDER_DATA_DIRECTION_FROM_TCP = '=>'

const DIRECTIONS =
  none:
    from_serial: no
    from_tcp: no
  serial:
    from_serial: yes
    from_tcp: no
  tcp:
    from_serial: no
    from_tcp: yes
  both:
    from_serial: yes
    from_tcp: yes



class Recorder extends StepTimer
  (@parent, pino, capture) ->
    logger = pino.child {category: 'Recorder'}
    super logger, 2s, no
    self = @
    self.logger = logger
    self.from_serial = no
    self.from_tcp = no
    xs = DIRECTIONS[capture]
    logger.info "xs => #{JSON.stringify xs}"
    return unless xs?
    {from_serial, from_tcp} = xs
    self.from_serial = from_serial
    self.from_tcp = from_tcp
    self.packets = []
    self.since = Date.now!
    self.filename = "/tmp/serial-tcp-proxy-#{self.since}.tsv"
    self.stream = stream = fs.createWriteStream self.filename
    stream.write "# start: #{new Date!}\n\n"
    logger.info "recording chunk data to #{self.filename.yellow}" if self.from_serial or self.from_tcp
    return

  save_data_from_serial: (chunk) ->
    {logger, from_serial, since, packets} = self = @
    return unless from_serial
    now = Date.now!
    uptime = now - since
    direction = RECORDER_DATA_DIRECTION_FROM_SERIAL
    packets.push {uptime, direction, chunk}
    # logger.info "packets = #{packets.length}"

  save_data_from_tcp: (chunk) ->
    {logger, from_tcp, since, packets} = self = @
    return unless from_tcp
    now = Date.now!
    uptime = now - since
    direction = RECORDER_DATA_DIRECTION_FROM_TCP
    packets.push {uptime, direction, chunk}
    # logger.info "packets = #{packets.length}"

  serialize_packet: (p) ->
    {uptime, direction, chunk} = p
    prefix = '!'
    ms = uptime % 1000
    ms = lodash.padStart ms, 3, '0'
    sec = Math.floor (uptime / 1000)
    sec = lodash.padStart sec, 10, '0'
    time = "#{sec}.#{ms}"
    # time = lodash.padStart uptime, 13, '0'
    hexes = (chunk.toString 'hex').toUpperCase!
    xs = [prefix, time, direction, hexes]
    return xs.join ' '

  execute: (done) ->
    {logger, packets, stream} = self = @
    self.packets = []
    xs = [ (self.serialize_packet p) for p in packets ]
    xs.push ''
    xs = xs.join '\n'
    self.wait_stream_drain = no
    logger.info "writing #{xs.length} bytes to local disk"
    cb = ->
      return if self.wait_stream_drain
      return done!
    ret = stream.write xs, 'utf8', cb
    return if ret
    self.wait_stream_drain = yes
    return stream.once 'drain', cb


module.exports = exports = Recorder
