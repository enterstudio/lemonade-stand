# lemonade-stand.coffee
# Copyright 2016 9165584 Canada Corporation <legal@fuzzy.ai>

express = require 'express'
path = require 'path'

_ = require 'lodash'
{ Databank } = require 'databank'
session = require 'express-session'
DatabankStore = require('connect-databank')(session)
Microservice = require 'fuzzy.ai-microservice'
APIClient = require 'fuzzy.ai'
version = require './version'

{ seller, buyer } = require './agents'

class LemonadeStand extends Microservice

  getName: ->
    "lemonade-stand"

  environmentToConfig: (env) ->
    config = super env

    _.extend config,
      apiServer: env['API_SERVER'] || 'https://api.fuzzy.ai'
      apiKey: env['API_KEY']
      buyerID: env['BUYER_AGENT_ID']

    config

  setupMiddleware: (exp) ->
    exp.apiClient = new APIClient
      root: @config.apiServer
      key: @config.apiKey

    # set up redis session
    @db = Databank.get @config.driver, @config.params
    @db.connect @config.params, (err) ->
      if err
        console.error "connection error"

    store = new DatabankStore @db, exp.log
    exp.use session
      secret: 's3kr3t'
      store: store
      resave: true
      saveUninitialized: true

    # Develpment mode tweaks
    if process.env.NODE_ENV == 'development'
      webpack = require('webpack')
      webpackConfig = require '../webpack.config'
      webpackConfig.entry.unshift('webpack-hot-middleware/client?reload=true')
      webpackConfig.plugins.push(new webpack.HotModuleReplacementPlugin())
      compiler = webpack(webpackConfig)

      exp.use require('webpack-dev-middleware')(compiler, {
        noInfo: true,
        publicPath: webpackConfig.output.publicPath
      })
      exp.use(require('webpack-hot-middleware')(compiler))

    exp.use express.static path.join(__dirname, '..', 'public')

  setupRoutes: (exp) ->
    exp.post '/data/seller', @_newSeller
    exp.post '/data/seller/evaluate', @_evaluateSeller
    exp.post '/data/seller/feedback', @_feedbackSeller
    exp.post '/data/buyer/evaluate', @_evaluateBuyer
    exp.get '/version', (req, res, next) ->
      res.json {name: 'lemonade-stand', version: version}


  startDatabase: (callback) ->
    callback null

  stopDatabase: (callback) ->
    callback null

  startCustom: (callback) ->
    client = @express.apiClient

    # Make sure we have the proper buyer agent.
    if @config.buyerID
      client.putAgent @config.buyerID, buyer, (err, agent) ->
        if err
          callback err
        else
          callback null
    else
      callback null

  _newSeller: (req, res, next) ->
    console.error req.session
    if req.session.sellerID
      res.json
        status: 'OK'
    else
      client = req.app.apiClient

      agent = seller
      agent.name = req.session.sid

      client.newAgent agent, (err, agent) ->
        if err
          next err
        else
          req.session.sellerID = agent.id
          res.json
            status: 'OK'

  _evaluateSeller: (req, res, next) ->
    client = req.app.apiClient
    client.evaluate req.session.sellerID, req.body, true, (err, evaluation) ->
      if err
        next err
      else
        req.session.lastEvalID = evaluation.meta.reqID
        res.json
          status: 'OK'
          evaluation: evaluation

  _feedbackSeller: (req, res, next) ->
    client = req.app.apiClient
    if not req.session.lastEvalID
      res.json
        status: 'OK'
    else
      evalID = req.session.lastEvalID
      client.feedback evalID, req.body, (err, feedback) ->
        if err
          next err
        res.json
          status: 'OK'
          feedback: feedback

  _evaluateBuyer: (req, res, next) ->
    client = req.app.apiClient
    config = req.app.config

    client.evaluate config.buyerID, req.body, (err, evaluation) ->
      if err
        next err
      else
        res.json
          status: 'OK'
          evaluation: evaluation

module.exports = LemonadeStand
