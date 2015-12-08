pty     = require 'pty'
bunyan  = require 'bunyan'
ssh2    = require 'ssh2'
log     = bunyan.createLogger name: 'sessionHandler'

STATUS_CODE = ssh2.SFTP_STATUS_CODE

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
        #handles = []
        console.log 'Client wants an SFTP session'
        sftpStream = accept()
        sftpStream.on 'OPEN', (reqid, filename, flags, attrs) ->
          log.info {sftp: 'OPEN', params: [reqid, filename, flags, attrs] }

        sftpStream.on 'OPENDIR', (reqid, folder) ->
          log.info {sftp: 'OPENDIR', args: arguments }
          #handle.writeUInt32BE(1, 0, true);
          #sftpStream.attrs(reqid, mode: 777, uid: 100, gid: 100, size: 0)
          #sftpStream.status(reqid, 0)
          #sftpStream.status(reqid+1, 0)
          sftpStream.handle reqid, new Buffer(folder)
          # sftpStream.name(reqid, [
          #   filename: '/test/file1'
          #   longname: '-rwxr--r-- 1 bar bar Dec 8 2015 file1'
          # ,
          #   filename: '/test/file2'
          #   longname: '-rwxr--r-- 1 bar bar Dec 8 2015 file2'
          # ])

        sftpStream.on 'READDIR', (reqid, handle) ->
          log.info {sftp: 'READDIR', args: arguments }
          folder = handle.toString()
          console.log 'readdir', folder
          sftpStream.name(reqid, [
            filename: 'file1'
            longname: '-rwxr--r-- 1 bar bar Dec 8 2015 file1'
            attrs:
              mode: 777
              uid: 100
              gid: 100
              size: 10
              atime: 1449583837
              mtime: 1449583837
          ,
            filename: 'file2'
            longname: '-rwxr--r-- 1 bar bar Dec 8 2015 file2'
            attrs:
              mode: 777
              uid: 100
              gid: 100
              size: 15
              atime: 1449583837
              mtime: 1449585837
          ])

        sftpStream.on 'FSTAT',  ->
          log.info {sftp: 'FSTAT', args: arguments }
        sftpStream.on 'LSTAT',  ->
          log.info {sftp: 'LSTAT', args: arguments }
        sftpStream.on 'READLINK',  ->
          log.info {sftp: 'READLINK', args: arguments }
        sftpStream.on 'REALPATH', (reqid)->
          log.info {sftp: 'REALPATH', args: arguments }
          #sftpStream.handle(reqid, new Buffer('/test'));
          sftpStream.name(reqid, [
            filename: '/test/'
            longname: '-rwxr--r-- 1 bar bar Dec 8 2015 test'
          ])

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
