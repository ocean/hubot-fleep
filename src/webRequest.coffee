
https = require 'https'
url = require 'url'
http = require 'http'
path = require 'path'

{EventEmitter} = require 'events'

Util = require './util'

module.exports = class WebRequest extends EventEmitter

  constructor: (@logger, @ticket, @token_id) ->
    super

  prepareReqOptions: (path, body = {}, headers = {}) ->
    host = 'fleep.io'
    headers = Util.merge {
      Host: host
      'User-Agent': 'hubot-fleep',
      'Content-Type': 'application/json'
    }, headers

    if @token_id?
      cookie = 'token_id='+@token_id
      @logger.debug "Setting cookie: #{cookie}"
      headers['Cookie'] = cookie
      
    reqOptions =
      agent: false
      hostname : host
      port     : 443
      path     : '/api/' + path
      method   : 'POST'
      headers  : headers
      
    if @ticket?
      @logger.debug "Setting ticket: #{@ticket}"
      body.ticket = @ticket
    
    # Encode JSON request body into a string format.
    # Only do this if it's not a file upload request
    unless headers['Content-Disposition']?
      body = new Buffer JSON.stringify(body)

    
    reqOptions.headers['Content-Length'] = body.length

    [reqOptions, body]


  post: (path, body, callback, headers = {}) ->
    @logger.debug 'Sending new POST request'

    [reqOptions, body] = this.prepareReqOptions path, body, headers

    @logger.debug 'Request options:'
    @logger.debug reqOptions
    
    # Send the request
    request = https.request reqOptions, (response) =>

      @logger.debug 'Got response from the server.'
      data = ''
      response.on 'data', (chunk) ->
        data += chunk
  
      response.on 'end', =>
        if response.statusCode >= 400
          @logger.error "Fleep API error : #{response.statusCode}"
          @logger.error data
          return
  
        @logger.debug 'Response headers:'
        @logger.debug response.headers
          
        data = JSON.parse data

        @logger.debug 'HTTPS response body:'
        @logger.debug data
          
        metaData = {}

        if response.headers['set-cookie']? and
        response.headers['set-cookie'][0]?
          @token_id = this.getCookie response.headers['set-cookie'][0]
          @logger.debug 'Saving cookie value for later use: token_id='+@token_id
          metaData['token_id'] = @token_id
          
        @logger.debug 'Calling callback of request '+reqOptions.path
        callback? null, data, metaData
  
        response.on 'error', (err) ->
          @logger.error 'HTTPS response error:', err
          callback? err, null
  
    request.end body, 'binary'
  
    request.on 'error', (err) =>
      @logger.error 'HTTPS request error:', err
      @logger.error err.stack
      callback? err

  
  uploadImage: (uri, callbackfunc) ->
    
    # Parse uri to it's components
    # See http://nodejs.org/api/url.html
    urlParts = url.parse uri, true
    
    http.get {host : urlParts.host, path: urlParts.path}, (resp) =>

      resp.setEncoding 'binary'
      imageData = ''

      resp.on 'data', (chunk) ->
        imageData += chunk
      
      resp.on 'end', =>
        
        request = new WebRequest(@logger, @ticket, @token_id)
  
        fileName = path.basename(urlParts.path).replace /[^0-9a-zA-Z.\-_]/g, '.'
        headers =
          'Content-Type': resp.headers['content-type'],
          'Content-Disposition' : "attachment; filename=#{fileName};"

        request.post(
          'file/upload?ticket='+@ticket+'&_method=PUT',
          imageData,
          callbackfunc,
          headers)

  getCookie: (header) ->
    @logger.debug 'Parsing cookie string ' + header
    parts = header.split ';'
    if parts[0]?
      parts = parts[0].split '='
      @logger.debug 'Token is ' + parts[1]
      parts[1]
