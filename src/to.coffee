
fs = require 'fs'
Stream = require 'stream'
utils = require './utils'

###

Writing data to a destination
=============================

The `csv().to` property provides functions to read from a CSV instance and
to write to an external destination. The destination may be a stream, a file
or a callback.

You may call the `to` function or one of its sub function. For example,
here are two identical ways to write to a file:

    csv.from(data).to('/tmp/data.csv');
    csv.from(data).to.path('/tmp/data.csv');

###
module.exports = (csv) ->

  ###

  `to(mixed)`
  -----------

  Write from any sort of destination. It should be considered as a convenient function
  which will discover the nature of the destination where to write the CSV data.

  If the parameter is a function, then the csv will be provided as the first argument
  of the callback. If it is a string, then it is expected to be a
  file path. If it is an instance of `stream`, it consider the object to be an
  output stream.

  Here's some examples on how to use this function:

      csv()
      .from('"1","2","3","4","5"')
      .to(function(data){ console.log(data) })

      csv()
      .from('"1","2","3","4","5"')
      .to('./path/to/file.csv')

      csv()
      .from('"1","2","3","4","5"')
      .to(fs.createWriteStream('./path/to/file.csv'))

  ###
  to = (mixed, options) ->
    error = false
    switch typeof mixed
      when 'string'
        to.path mixed, options
      when 'object'
        if mixed instanceof Stream
        then to.stream mixed, options
        else error = true
      when 'function'
        to.string mixed, options
      else
        error = true
    csv.error new Error "Invalid mixed argument in from" if error
    csv

  to.options = (options) ->
    if options?
      utils.merge csv.options.to, options
      if csv.options.to.lineBreaks
        console.log 'To options linebreaks is replaced by rowDelimiter'
        unless csv.options.to.rowDelimiter
          csv.options.to.rowDelimiter = csv.options.to.lineBreaks
      switch csv.options.to.rowDelimiter
        when 'auto'
          csv.options.to.rowDelimiter = null
        when 'unix'
          csv.options.to.rowDelimiter = "\n"
        when 'mac'
          csv.options.to.rowDelimiter = "\r"
        when 'windows'
          csv.options.to.rowDelimiter = "\r\n"
        when 'unicode'
          csv.options.to.rowDelimiter = "\u2028"
      csv
    else
      csv.options.to

  ###

  `to.string(callback, [options])`
  ------------------------------

  Provide the output string to a callback.

      csv()
      .from( '"1","2","3"\n"a","b","c"' )
      .to.string( function(data, count){} )

  Callback is called with 2 arguments:
  *   data      Entire CSV as a string
  *   count     Number of stringified records

  ###
  to.string = (callback, options) ->
    @options options
    data = []
    stream = new Stream
    stream.writable = true
    stream.write = (d) ->
        data.push d
        true
    stream.end = ->
        callback data.join(''), csv.state.countWriten
    csv.pipe stream
    csv

  ###

  `to.stream(stream, [options])`
  ------------------------------

  Write to a stream. Take a writable stream as first argument and
  optionally an object of options as a second argument.

  Additionnal options may be defined. See the [`readable.pipe`
  documentation][srpdo] for additionnal information.

  [srpdo]: http://www.nodejs.org/api/stream.html#stream_readable_pipe_destination_options

  ###
  to.stream = (stream, options) ->
    @options options
    csv.pipe stream, csv.options.to
    stream.on 'error', (e) ->
      csv.error e
    stream.on 'close', ->
      # todo, mark this as deprecated
      csv.emit 'close', csv.state.count
    stream.on 'finish', ->
      csv.emit 'finish', csv.state.count
    csv

  ###

  `to.path(path, [options])`
  --------------------------

  Write to a path. Take a file path as first argument and optionally an object of
  options as a second argument. The `close` event is sent after the file is written.
  Relying on the `end` event is incorrect because it is sent when parsing is done
  but before the file is written.

  Additionnal options may be defined with the following default:

      { flags: 'w',
        encoding: null,
        mode: 0666 }

  See the [`fs.createReadStream` documentation][fscpo] for additionnal information.

  [fscpo]: http://www.nodejs.org/api/fs.html#fs_fs_createwritestream_path_options

  Example to modify a file rather than replacing it:

      csv()
      .to.file('my.csv', {flags:'r+'})
      .write(['hello', 'node'])
      .end()

  ###
  to.path = (path, options) ->
    # Merge user provided options
    @options options
    # Clone options
    options = utils.merge {}, csv.options.to
    # Delete end property which otherwise overwrite `stream.end()`
    delete options.end
    # Create the write stream
    stream = fs.createWriteStream path, options
    csv.to.stream stream, null
    csv

  ###

  `to.array(path, [options])`
  --------------------------

  Provide the output string to a callback.

      csv()
      .from( '"1","2","3"\n"a","b","c"' )
      .to.array( function(data, count){} )

  Callback is called with 2 arguments:
  *   data      Entire CSV as an array of records
  *   count     Number of stringified records

  ###
  to.array = (callback, options) ->
    @options options
    headers = []
    headerSeen = false;
    records = []
    csv.on 'record', (record) ->
      # Filter and reorder with the columns option
      # Note, stringifier is doing sth similar to transformat the
      # incoming record based on column spec. This logic
      # should be shared. A correct place could be the transformer step.
      if @options.to.columns
        # Added to keep the default behavious in the check below.
        headerSeen = true
        if Array.isArray record
          _record = record
          record = {}
          for column, i in @options.to.columns
            record[column] = _record[i]
        else
          _record = record
          record = {}
          for column in @options.to.columns
            record[column] = _record[column]
      else if @options.to.header
        if !headerSeen
          # We have to check this because it seems like the first record we get is '[]'
          # and THEN we get the header record.
          if record[0]?
            headerSeen = true
            headers = record
            return headers
        else
          if Array.isArray record
            _record = record
            record = {}
            for item, i in _record
              record[headers[i]] = _record[i]
          else
            # This bit looks the same as the bit just above
            # I don't know how to test it so I don't know if it works
            # The logic is pretty simple though, and having it the same might just be right
            _record = record
            record = {}
            for item, i in _record
              record[headers[i]] = _record[i]
      # This stops us getting '[]' as the first record when doing header-based columns
      if @options.to.header
        if headerSeen == true
          records.push record
      else
        records.push record
    csv.on 'end', ->
      callback records, csv.state.countWriten
    csv

  ###

  to.object(path, [options])`
  --------------------------

  Provide the output string to a callback.

      csv()
      .from( '"Name","Age"\n"a","12"' )
      .to.object(function(data, count){}, )

  Callback is called with 2 arguments:
  *   data      Entire CSV as an object of records, addressable by 'objName'
  *   count     Number of stringified records
  ###
  to.object = (callback, options) ->
    @options options
    headers = []
    headerSeen = false;
    records = {}
    # Error out if the option wasn't set.
    if !options.objname
      return callback {"error": "You need to specify objName: to.object(callback, objName);"}, 0
    csv.on 'record', (record) ->
      # Filter and reorder with the columns option
      # Note, stringifier is doing sth similar to transformat the
      # incoming record based on column spec. This logic
      # should be shared. A correct place could be the transformer step.
      if @options.to.columns
        # I kept the header row in for compatability but it was too ugly, so removed.
        if !headerSeen
          # We have to check this because it seems like the first record we get is '[]'
          # and THEN we get the header record.
          if record[0]?
            headerSeen = true
            headers = record
            return headers
        else
          if Array.isArray record
            _record = record
            record = {}
            for column, i in @options.to.columns
              record[column] = _record[i]
          else
            _record = record
            record = {}
            for column in @options.to.columns
              record[column] = _record[column]
      else if @options.to.header
        if !headerSeen
          # We have to check this because it seems like the first record we get is '[]'
          # and THEN we get the header record.
          if record[0]?
            headerSeen = true
            headers = record
            return headers
        else
          if Array.isArray record
            _record = record
            record = {}
            for item, i in _record
              record[headers[i]] = _record[i]
          else
            # This bit looks the same as the bit just above
            # I don't know how to test it so I don't know if it works
            # The logic is pretty simple though, and having it the same might just be right
            _record = record
            record = {}
            for item, i in _record
              record[headers[i]] = _record[i]
      # This stops us getting '[]' as the first record when doing header-based columns
      if @options.to.header
        if headerSeen == true
          records[record[@options.to.objname].trim()] = record
      else
        records[record[@options.to.objname].trim()] = record
    csv.on 'end', ->
      callback records, csv.state.countWriten
    csv

  to


