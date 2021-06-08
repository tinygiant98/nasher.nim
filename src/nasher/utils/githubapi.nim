import std/[browsers, httpclient, json, options, os, strutils]
import cli

type
  Auth* = object
    user*: string
    token*: string
    http: HttpClient

const
  apiUrl = "https://api.github.com/$1" #{apiRepository}
  apiToken = "https://github.com/settings/tokens/new"
  apiRepository = "repos/$1/$2" #{owner}/{repo}
  apiUser = "user"
  apiTokenFile = getConfigDir() / "nasher" / "libraries" / "github_api_token"   # share with libraries.nim

proc `/`(head, tail: string): string {.noSideEffect.} =
  ## Concatenates head and tail with forward slash instead of standard path separator.
  ## For use in URL contruction for API request
  head & "/" & tail

proc enterNewToken(auth: var Option[Auth]) =
  ## Allows user to enter a github api token
  auth.get.token = ask("Enter GitHub API token", allowBlank = false)
  debug("Saving github API token to $1" % apiTokenFile)
  writeFile(apiTokenFile, auth.get.token)

proc createNewToken(auth: var Option[Auth]) =
  ## Opens default browser to github.com api token creation site
  display("Info", "Please create a personal access token on GitHub.com.  To use the automated functions " &
    "within nasher, this token must be granted, at a minimum, access to public repositories.  When you're " &
    "ready, press enter and you will be taken to the GitHub website to create this token.  If you do not " &
    "already have a GitHub account, you must create one.  After you create your token, copy it and return " &
    "to enter and save it for future use.")
  if askIf("Press enter to continue...", default = Yes):
    openDefaultBrowser(apiToken)
    auth.enterNewToken()
  else:
    fatal("user opted to end operation")

proc getAuth*: Option[Auth] =
  ## Collects minimum information to be able to use GitHub's REST API
  try:
    result = some(Auth())
    result.get.token = readFile(apiTokenFile).strip()
    debug("Loading github API token from $1" % apiTokenFile)
  except IOError:
    const
      enter = "Enter a GitHub API token"
      create = "Create a new GitHub API token"
      exit = "Exit"

    let question = "What would you like to do?"
    let choices = [enter, create, exit]

    error("GitHub API token cannot be found")
    let choice = choose(question, choices)
    
    case choice
    of enter:
      result.enterNewToken()
    of create:
      result.createNewToken()
    of exit:
      fatal("user opted to end operation")

  # http, requires github token
  result.get.http = newHttpClient()
  result.get.http.headers = newHttpHeaders({
    "Authorization": "token $1" % result.get.token,
    "Content-Type": "application/x-www-form-urlencoded",
    "Accept": "application/vnd.github.v3+json"
  })

  # user, requires the http headers
  let userData = result.get.http.getContent(apiUrl % apiUser).parseJson()
  result.get.user = userData["login"].getStr()

proc verify*(auth: var Option[Auth]): Option[Auth] =
  if auth.isNone(): getAuth()
  else: auth

proc apiGetContent*(auth: var Option[Auth], user, repo, primaryKey: string, secondaryKey = ""): JsonNode =
  ## Sends an API getContent request to github.com
  result = nil
  debug("Attempting to send http getContent request: $1" % apiUrl % apiRepository % [user, repo])

  if auth.verify().isSome():
    try:
      let 
        #auth = getAuth()
        apiResult = auth.get.http.getContent(apiUrl % apiRepository % [user, repo]).parseJson()

      if secondaryKey == "":
        result = apiResult{primaryKey}
      else:
        result = apiResult{primaryKey}{secondaryKey}

      debug("getContent request successful")
    except HttpRequestError:
      debug("getContent error: " & getCurrentException().msg)
      result = nil
  else:
    debug("getContent request failed; unable to create Auth")

proc apiPostContent*(auth: var Option[Auth], user, repo, request: string, body = ""): string {.discardable.} =
  ## Sends an API postContent request to github.com
  debug("Attempting to send http postContent request: $1" % apiUrl % apiRepository % [user, repo] / request)

  if auth.verify().isSome():
    try:
      let
        url = apiUrl % apiRepository % [user, repo] / request
        auth = getAuth()
      
      result = auth.get.http.postContent(url, body)
      debug("postContent request successful")
    except HttpRequestError:
      debug("postContent error: " & getCurrentException().msg)
  else:
    debug("postContent request failed; unable to create Auth")

proc apiDeleteContent*(auth: var Option[Auth], user, repo: string) =
  ## Sends an API deleteContent request to github.com
  debug("Attempting to send http deleteContent request: $1" % apiUrl % apiRepository % [user, repo])

  if auth.verify().isSome():
    try:
      let
        url = apiUrl % apiRepository % [user, repo]
        auth = getAuth()

      discard auth.get.http.delete(url)
      debug("deleteContent request successful")
    except HttpRequestError:
      debug("deleteContent error: " & getCurrentException().msg)
  else:
    debug("deleteContent request failed; unable to create Auth")
