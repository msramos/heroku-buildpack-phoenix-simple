cleanup_cache() {
  if [ $clean_cache = true ]; then
    info "clean_cache option set to true."
    info "Cleaning out cache contents"
    rm -rf $cache_dir/npm-version
    rm -rf $cache_dir/node-version
    rm -rf $cache_dir/phoenix-static
    rm -rf $cache_dir/yarn-cache
    cleanup_old_node
  fi
}

load_previous_npm_node_versions() {
  if [ -f $cache_dir/npm-version ]; then
    old_node=$(<$cache_dir/node-version)
  fi
}

download_node() {
  local platform=linux-x64

  if [ ! -f ${cached_node} ]; then
    echo "Resolving node version $node_version..."
    if ! read number url < <(curl --silent --get --retry 5 --retry-max-time 15 --data-urlencode "range=$node_version" "https://nodebin.herokai.com/v1/node/$platform/latest.txt"); then
      fail_bin_install node $node_version;
    fi

    echo "Downloading and installing node $number..."
    local code=$(curl "$url" -L --silent --fail --retry 5 --retry-max-time 15 -o ${cached_node} --write-out "%{http_code}")
    if [ "$code" != "200" ]; then
      echo "Unable to download node: $code" && false
    fi
  else
    info "Using cached node ${node_version}..."
  fi
}

cleanup_old_node() {
  local old_node_dir=$cache_dir/node-$old_node-linux-x64.tar.gz

  # Note that $old_node will have a format of "v5.5.0" while $node_version
  # has the format "5.6.0"

  if [ $clean_cache = true ] || [ $old_node != v$node_version ] && [ -f $old_node_dir ]; then
    info "Cleaning up old Node $old_node and old dependencies in cache"
    rm $old_node_dir
    rm -rf $cache_dir/node_modules
  fi
}

install_node() {
  info "Installing Node $node_version..."
  tar xzf ${cached_node} -C /tmp
  local node_dir=$heroku_dir/node

  if [ -d $node_dir ]; then
    echo " !     Error while installing Node $node_version."
    echo "       Please remove any prior buildpack that installs Node."
    exit 1
  else
    mkdir -p $node_dir
    # Move node (and npm) into .heroku/node and make them executable
    mv /tmp/node-v$node_version-linux-x64/* $node_dir
    chmod +x $node_dir/bin/*
    PATH=$node_dir/bin:$PATH
  fi
}

install_yarn() {
  local dir="$1"

  echo "Downloading and installing yarn..."
  local download_url="https://yarnpkg.com/latest.tar.gz"
  local code=$(curl "$download_url" -L --silent --fail --retry 5 --retry-max-time 15 -o /tmp/yarn.tar.gz --write-out "%{http_code}")
  if [ "$code" != "200" ]; then
    echo "Unable to download yarn: $code" && false
  fi
  rm -rf $dir
  mkdir -p "$dir"
  # https://github.com/yarnpkg/yarn/issues/770
  if tar --version | grep -q 'gnu'; then
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1 --warning=no-unknown-keyword
  else
    tar xzf /tmp/yarn.tar.gz -C "$dir" --strip 1
  fi
  chmod +x $dir/bin/*
  PATH=$dir/bin:$PATH
  echo "Installed yarn $(yarn --version)"
}

install_and_cache_deps() {
  info "Installing and caching node modules"
  cd $assets_dir
  if [ -d $cache_dir/node_modules ]; then
    mkdir -p node_modules
    cp -r $cache_dir/node_modules/* node_modules/
  fi

  install_yarn_deps

  cp -r node_modules $cache_dir
  PATH=$assets_dir/node_modules/.bin:$PATH
}

install_yarn_deps() {
  yarn install --cache-folder $cache_dir/yarn-cache --pure-lockfile 2>&1
}

cache_versions() {
  info "Caching versions for future builds"
  echo `node --version` > $cache_dir/node-version
  echo `yarn --version` > $cache_dir/yarn-version
}

finalize_node() {
  if [ $remove_node = true ]; then
    remove_node
  else
    write_profile
  fi
}

write_profile() {
  info "Creating runtime environment"
  mkdir -p $build_dir/.profile.d
  local export_line="export PATH=\"\$HOME/.heroku/node/bin:\$HOME/.heroku/yarn/bin:\$HOME/bin:\$HOME/$phoenix_relative_path/node_modules/.bin:\$PATH\""
  echo $export_line >> $build_dir/.profile.d/phoenix_static_buildpack_paths.sh
}

remove_node() {
  info "Removing node and node_modules"
  rm -rf $assets_dir/node_modules
  rm -rf $heroku_dir/node
}
