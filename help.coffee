path = require 'path'
request = require 'request'
fs = require 'fs'
child_process = require 'child_process'
config = require './config.json'

# What Shall do in this Section
# 1 Download RELEASES from Github, And generate RELEASE List from RELEASES
# OR
# 1 According To The Listed Names, Download RELEASES from Github
# 2 Unzip RELEASE file to target directory.
# 3 Generate FROM_PATH and TO_PATH for lib.
# 4 DEPLOY the ARCHIVES to OSS.

# For Step1, Select 1.

generate_path = (app_name, release_name) ->
  # 3 Generate FROM_PATH and TO_PATH
  from_path = path.join config.target_root, app_name, 'source', path.basename(release_name, ".tar.gz")
  to_path = path.join config.target_root, app_name, 'target', path.basename(release_name, ".tar.gz")

  # Make the dir exists.
  try fs.mkdirSync path.join config.target_root, app_name

  try fs.mkdirSync path.join config.target_root, app_name, 'source'
  try fs.mkdirSync path.join config.target_root, app_name, 'target'

  try fs.mkdirSync from_path
  try fs.mkdirSync to_path

  return value = 
    from_path: from_path,
    to_path: to_path


prepare = (app_name, running_data, source = 'gitlab') ->
  running_data.child_progress = 0
  if source == 'github'
    api_source = "https://api.github.com/repos/moecube/" + app_name + "/releases/latest"
    # 0 Download RELEASE list from Github
    api_response = await new Promise (resolve, reject) ->
      request { url: api_source, headers: { 'User-Agent': 'moecube-ygopro-packager' }}, (err, res, body) ->
        resolve JSON.parse body
    from_path_sources = api_response.assets.map (asset) -> { name: asset.name, url: asset.browser_download_url }
  else if source == 'gitlab'
    api_source = "http://ygopro-release-helper:3000/release"
    api_response = await new Promise (resolve, reject) ->
      request { url: api_source, headers: { 'Authorization': process.env.MYCARD_RELEASE_TOKEN } }, (err, res, body) -> resolve JSON.parse body
    from_path_sources = api_response.files.map (asset) -> { name: asset.filename, url: "https://cdn01.moecube.com/mcpro/#{asset.filename}" }
  else 
    throw "Can't recognize source #{source}"

  # 0 Build Download Directory
  try fs.mkdirSync path.join config.target_root, app_name
  download_target_path = path.join config.target_root, app_name, 'source'
  try fs.mkdirSync download_target_path

  # 0 Generate download target path
  asset.download_target = path.join download_target_path, asset.name for asset in from_path_sources
  console.log "Packager see " + from_path_sources.length + " downloading releases."

  # 1 Execute Download Step（via browser_download_url）
  running_data.child_progress += 1
  for from_path_source in from_path_sources
    await new Promise (resolve, reject) ->
      request(from_path_source.url).pipe(fs.createWriteStream from_path_source.download_target).on 'close', ->
        resolve 'ok'
      console.log "Downloading " + app_name + "/" + from_path_source.name + "(" + from_path_source.url + ")"
    running_data.child_progress += 1
  console.log app_name + " Download step finished."
  
  # 2 Unzip Release Files
  running_data.child_progress = 100
  for asset in from_path_sources
    console.log "Unzipping file " + asset.download_target
    asset.dirname = path.join path.dirname(asset.download_target), path.basename(asset.download_target, ".tar.gz")
    command = "tar --warning=no-unknown-keyword -zxf " + asset.download_target + " -C " + asset.dirname
    console.log "Executing command #{command}" if process.env.NODE_ENV == "DEBUG"
    try fs.mkdirSync asset.dirname
    await asyncExecute command
    running_data.child_progress += 1
  console.log "Unzip step finished."

  # 1 Generate RELEASE List from RELEASES
  from_path_sources.map (asset) ->
    release_name: asset.name
    b_name: extractBName asset.name

deploy = (dir) ->
  # 4 DEPLOY ARCHIVES to OSS.
  # command = mustache.render config.deploy_command, { source_path: dir }
  command = config.deploy_command.replace "{{source_path}}", dir
  console.log "Executing deploy command #{command}"
  await asyncExecute command, { stdio: 'ignore' }


asyncExecute = (command, config) ->
  config = {} unless config
  new Promise (resolve, reject) ->
    child_process.exec command, config, (err, stdout, stderr) ->
      if err then reject err else resolve stdout

# Only for ygopro.
# Extract 'linux-en-US' from 'ygopro-1.033.F-1-linux-en-US.tar.gz'
reg = new RegExp '1\\.03\\d\\.[0-9A-H]\\-\\d+\\-'
extractBName = (release_name) ->
  match = reg.exec release_name
  start_position = match.index + match[0].length
  name = release_name.substring(start_position, release_name.length - 7)
  # MAGIC CHANGE
  name.replace 'osx', 'darwin'


module.exports.deploy = deploy
module.exports.prepare = prepare
module.exports.generate_path = generate_path
