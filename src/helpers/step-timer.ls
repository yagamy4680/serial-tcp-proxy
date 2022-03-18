##
# Copyright (c) 2019-2021 T2T Inc. All rights reserved
# https://www.t2t.io
# https://tic-tac-toe.io
# Taipei, Taiwan
#
class StepTimer
  (@logger, @interval, @first_run=no) ->
    self = @
    self.countdown = interval
    self.executing = no
    return
  
  start: ->
    {logger, first_run} = self = @
    f = -> return self.on_timeout!
    if first_run
      try
        (err) <- self.execute
        if err?
          logger.error err
          console.dir err
        self.timer = setInterval f, 1000ms
      catch
        logger.error e
        console.dir e
    else
      self.timer = setInterval f, 1000ms

  execute: (done) ->
    return done!

  on_timeout: ->
    {logger, countdown, executing} = self = @
    return if executing
    self.countdown = countdown - 1
    return if self.countdown > 0
    self.executing = yes
    self.countdown = self.interval
    try
      self.execute (err) ->
        if err?
          logger.error err
          console.dir err
        self.executing = no
    catch
      logger.error e
      console.dir e
      self.executing = no


module.exports = exports = {StepTimer}
