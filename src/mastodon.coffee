masto = require 'mastodon-api'
process = require 'process'
striptags = require 'striptags'
request = require 'request-promise'

try
    {Adapter, TextMessage} = require 'hubot'
catch
    prequire = require 'parent-require'
    {Adapter, TextMessage} = prequire 'hubot'

class Mastodon extends Adapter

    constructor: ->
        super

    buildBody: (envelope, strings...) ->
        str = strings[0]

        body =
            status: "@#{envelope.user} #{str}"
            sensitive: envelope.message.metadata.sensitive
            spoiler_text: envelope.message.metadata.spoiler_text
            visibility: envelope.message.metadata.visibility
        return body

    registerMedia: (media) =>
        request.head(media).then (headers) =>
            @robot.logger.debug 'head'
            @robot.logger.debug headers
            if headers['content-type'].startsWith 'image'
                return @api.post('media', file: request.get media)
        .then (response) =>
            @robot.logger.debug 'registerMedia'
            @robot.logger.debug response
            return response?.data?.id
        .catch (response) =>
            @robot.logger.error 'registerMedia ERROR'
            @robot.logger.error response

    send: (envelope, strings...) ->
        @reply envelope, strings...

    reply: (envelope, strings...) ->
        @robot.logger.debug envelope
        @robot.logger.debug strings

        body = @buildBody envelope, strings...
        body.in_reply_to_id = envelope.message.id

        result = strings.some (str) -> str.startsWith 'http'

        if result
            media_ids = (@registerMedia media for media in strings when media.startsWith 'http')
            Promise.all(media_ids).then (ids) =>
                body.media_ids = ids
                @robot.logger.debug ids

                return @api.post 'statuses', body
            .then (response) =>
                @robot.logger.debug 'Success!'
            .catch (response) =>
                @robot.logger.error response

        else
            @api.post('statuses', body).then (response) =>
                @robot.logger.debug 'Success!'
            .catch (response) =>
                @robot.logger.error response

    connect: ->
        @listener = @api.stream 'streaming/user'

        @listener.on 'message', @messageListener

        @listener.on 'error', (err) =>
            @robot.logger.info err

    messageListener: (toot) =>
        if toot.event isnt 'notification'
            return

        if toot.data.type isnt 'mention'
            return

        @robot.logger.debug toot
        @robot.logger.debug toot.data.status.mentions

        user = toot.data.account.acct
        display_name = toot.data.account.display_name
        text = striptags toot.data.status.content
        # remove all name references
        text = text.replace /@(\S+)/ig, ''
        # clean up whitespace
        text = text.replace /[ ][ ]+/g, ' '
        text = text.trim()
        text = "#{display_name}: #{text}"
        @robot.logger.debug text
        
        id = toot.data.status.id

        metadata =
            in_reply_to_id: toot.data.status.in_reply_to_id
            sensitive: toot.data.status.sensitive
            spoiler_text: toot.data.status.spoiler_text
            visibility: toot.data.status.visibility
        msg = new TextMessage user, text, id
        msg.metadata = metadata

        @robot.receive msg

    run: ->
        options =
            access_token: process.env.HUBOT_MASTODON_ACCESS_TOKEN
        @api = new masto options

        @connect()

        @emit 'connected'

exports.use = (robot) ->
    new Mastodon robot
