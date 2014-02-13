impromptu = require 'impromptu'
git = require 'impromptu-git'

async = require 'async'
read = require 'read'
request = require 'request'

module.exports = impromptu.plugin.create (github) ->
  rGitHubUrl = /^(?:git@github.com:|https:\/\/github.com\/)([^\/]+)\/([^\/]+)\.git/

  github.register '_parseRemoteUrl',
    update: (done) ->
      git.remoteUrl (err, url) ->
        return done err if err

        results = url.match rGitHubUrl
        return done err, null unless results

        done err,
          user: results[1]
          repo: results[2]

  github.register 'isGitHub',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, !!results

  github.register 'remoteUser',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.user

  github.register 'remoteRepo',
    update: (done) ->
      github._parseRemoteUrl (err, results) ->
        done err, results?.repo

  github.register 'token',
    update: ->
      process.env.IMPROMPTU_GITHUB_TOKEN

  requestGitHub = (path, options, done) ->
    unless done
      done = options
      options = null

    github.token (err, token) ->
      return done err if err or !token

      options ?= {}
      options.uri = "https://api.github.com/#{path}"
      options.json = true
      options.qs ?= {}
      options.qs.access_token = token
      options.headers = {
        'User-Agent': 'Impromptu-GitHub'
      }
      request options, done

  github.register 'ci',
    cache: 'repository'
    expire: 60
    update: (done) ->
      git.remoteBranch (err, branch) ->
        return done err, branch if err or not branch

        async.parallel [
          github._parseRemoteUrl,
          git.branch
        ], (err, results) ->
          [remote, branch] = results
          requestGitHub "repos/#{remote.user}/#{remote.repo}/statuses/#{branch}", (err, response, body) ->
            return done err, '' unless body and body.length
            done err, body[0].state

  requestFirstPullRequest = (remote, branch, state, done) ->
    requestGitHub "repos/#{remote.user}/#{remote.repo}/pulls",
      qs:
        head: "#{remote.user}:#{branch}"
        state: if state == 'closed' then 'closed' else 'open' # ensures a valid state
    , (err, response, body) ->
      if body and body.length
        done err, body[0]
      else
        done err, null

  github.register '_pullRequest',
    cache: 'repository'
    expire: 60
    update: (done) ->
      async.parallel [
        github._parseRemoteUrl,
        git.remoteBranch,
        git.branch
      ], (err, results) ->
        return done err, null if err

        [remote, remoteBranchWithOrigin, localBranch] = results
        remoteBranch = remoteBranchWithOrigin.replace(/^[^\/]+\//, '')
        branch = remoteBranch || localBranch

        requestFirstPullRequest remote, branch, 'open', (err, pullRequest) ->
          return done err, null if err

          # Return the first open pull request we find.
          return done err, pullRequest if pullRequest

          # If we didn't find an open pull request, search for closed ones.
          requestFirstPullRequest remote, branch, 'closed', (err, pullRequest) ->
            done err, pullRequest || null

  github.register 'pullRequestNumber',
    update: (done) ->
      github._pullRequest (err, pullRequest) ->
        done err, if pullRequest then pullRequest.number else null
