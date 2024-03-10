module commands {
  use std log debug
  use std log info
  use std log warning
  use std log error
  use std log critical

  export def "gh fetch" [
    owner:string,
    repo:string,
    path:string,
    --token (-t): string,
   ] {
    let base_url = "https://api.github.com/repos"
    mut headers = []
    let token = $env.GITHUB_TOKEN

    if ($token != null) {
      $headers = ($headers | append [ "Authorization" $"token ($token)" ])
    }
    let url = $"($base_url)/($owner)/($repo)/($path)"
    http get --headers $headers $url
  }

  export def save-zephyr-release-assets [
    release:string,
  ] {
    let release_data = (gh fetch "zephyrproject-rtos" "sdk-ng" $"releases/tags/($release)")
    let version = ($release_data.tag_name)
    log info $"fetching hashes for ($version)"
    let hashes =  ($release_data.assets
      | where name == "sha256.sum"
      | get browser_download_url.0
      | http get $in
      | from ssv --noheaders
      | rename sha256 name
    )

    $release_data.assets
      | select name browser_download_url
      | rename name url
      | join $hashes name name
      | save $"zephyr-assets/($version).json"
  }

  export def get-all-zephyr-release-hashes [] {
    gh fetch "zephyrproject-rtos" "sdk-ng" "releases"
      | where draft == false and prerelease == false
      | get tag_name
      | par-each {|e| save-zephyr-release-assets $e }
      | ignore
  }
}

use commands *

get-all-zephyr-release-hashes
