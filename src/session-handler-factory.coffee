pty     = require 'pty'
bunyan  = require 'bunyan'
log     = bunyan.createLogger name: 'sessionHandler'

spaces = (text, length) ->(' ' for i in [0..length-text.length]).join ''
header = (container) ->
  "\r\n" +
  " ###############################################################\r\n" +
  " ## Docker SSH ~ Because every container should be accessible ##\r\n" +
  " ###############################################################\r\n" +
  " ## container | #{container}#{spaces container, 45}##\r\n" +
  " ###############################################################\r\n" +
  "\r\n"

module.exports = (container, shell) ->
  instance: ->
    session = null
    channel = null
    term = null
    isClosing = false

    closeChannel = ->
      log.info {container: container}, 'Closing channel'
      isClosing = true
      channel.end() if channel
    stopTerm = ->
      log.info {container: container}, 'Stop terminal'
      term.kill 'SIGKILL' if term

    close: -> stopTerm()
    handler: (accept, reject) ->
      session = accept()

      session.once 'exec', (accept, reject, info) ->
        log.warn {container: container, command: info.command}, 'Client tried to execute a single command with ssh-exec. This is not (yet) supported by Docker-SSH.'
        stream = accept()
        stream.stderr.write "'#{info.command}' is not (yet) supported by Docker-SSH\n"
        stream.exit 0
        stream.end()

      session.on 'sftp', (accept, reject) ->
        console.log 'Client wants an SFTP session'
        sftpStream = accept()
        sftpStream.on 'OPEN', (reqid, filename, flags, attrs) ->
          log.info {sftp: 'OPEN', params: [reqid, filename, flags, attrs] }
        sftpStream.on 'OPENDIR',  ->
          log.info {sftp: 'OPENDIR', args: arguments }
        sftpStream.on 'READDIR',  ->
          log.info {sftp: 'READDIR', args: arguments }
        sftpStream.on 'FSTAT',  ->
          log.info {sftp: 'FSTAT', args: arguments }
        sftpStream.on 'LSTAT',  ->
          log.info {sftp: 'LSTAT', args: arguments }
        sftpStream.on 'READLINK',  ->
          log.info {sftp: 'READLINK', args: arguments }
        sftpStream.on 'REALPATH', ->
          log.info {sftp: 'REALPATH', args: arguments }


      session.on 'err', (err) ->
        log.error {container: container}, err

      session.on 'shell', (accept, reject) ->
        log.info {container: container}, 'Opening shell'
        channel = accept()
        channel.write "#{header container}"

        term = pty.spawn 'docker', ['exec', '-ti', container, shell], {}
        term.write 'export TERM=linux;\n'
        term.write 'export PS1="\\w $ ";\n\n'

        term.on 'exit', ->
          log.info {container: container}, 'Terminal exited'
          closeChannel()

        term.on 'error', (err) ->
          log.error {container: container}, 'Terminal error', err
          closeChannel()

        forwardData = false
        setTimeout (-> forwardData = true; term.write '\n'), 500
        term.on 'data', (data) ->
          if forwardData
            channel.write data

        channel.on 'data', (data) ->
          term.write data

        channel.on 'error', (e) ->
          log.error {container: container}, 'Channel error', e

        channel.on 'exit', ->
          log.info {container: container}, 'Channel exited'
          stopTerm()

      session.on 'pty', (accept, reject, info) ->
        x = accept()

      session.on 'window-change', (accept, reject, info) ->
        log.info {container: container}, 'window-change', info
        if term
          term.resize info.cols, info.rows
