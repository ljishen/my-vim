#!/usr/bin/env bash

set -eu -o pipefail

ID_LIKE=$( grep -oP '^ID_LIKE=\K\w+' /etc/os-release 2> /dev/null )
family=$( echo "$ID_LIKE" | tr '[:upper:]' '[:lower:]' )
if [ "$family" != "debian" ]; then
    echo "Operation aborted because the current OS is not a Debian-based distribution."
    exit 0
fi

jdk_pkgs=( )
# javac is used for syntastic checker for .java file
if ! hash javac 2>/dev/null; then
    jdk_pkgs=( openjdk-8-jdk openjdk-8-jre-headless )
fi

# perl for Checkpatch (syntax checking for C)
# gcc for syntax checking of c
# g++ for syntax checking of c++
# python3-pip, python3-setuptools and python3-wheel
#    are used for installing/building python packages (e.g. jsbeautifier, flake8)
# cppcheck for syntax checking of c and c++
# exuberant-ctags for Vim plugin Tagbar (https://github.com/majutsushi/tagbar#dependencies)
# clang-format is used by plugin google/vim-codefmt
# python3-dev is required to build typed-ast, which is required by jsbeautifier
# python-dev, cmake and build-essential are used for compiling YouCompleteMe(YCM)
#     with semantic support in the following command:
#     /bin/sh -c $HOME/.vim/bundle/YouCompleteMe/install.py
# libffi-dev and libssl-dev is required to build ansible-lint

## shellcheck for syntax checking of sh
sudo apt-get update && sudo apt-get install -y --no-install-recommends \
        curl \
        vim-nox \
        git \
        perl \
        g++ \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        cppcheck \
        exuberant-ctags \
        clang-format \
        python-dev \
        python3-dev \
        build-essential \
        cmake \
        libffi-dev \
        libssl-dev \
        shellcheck \
        ${jdk_pkgs[@]+"${jdk_pkgs[@]}"} \
    && sudo apt-get clean \
    && sudo rm -rf /var/lib/apt/lists/*


# Get the full directory name of the current script
# See https://stackoverflow.com/questions/59895/getting-the-source-directory-of-a-bash-script-from-within
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Install Vundle and Plugins
cp "${SCRIPT_DIR}"/../.vimrc "$HOME"
rm -rf "${HOME}"/.vim/bundle/Vundle.vim && \
    git clone https://github.com/VundleVim/Vundle.vim.git "${HOME}"/.vim/bundle/Vundle.vim && \
    vim +PluginClean! +PluginInstall! +qall && \
    sed -i 's/"#//g' "$HOME"/.vimrc


# Remove the old exported envs first
sed -i '/ljishen\/my-vim/,/#### END ####/d' "$HOME"/.profile

# Delete all trailing blank lines at end of file
#   http://sed.sourceforge.net/sed1line.txt
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HOME"/.profile

printf "\\n\\n#### Export Variables for Vim Plugins (https://github.com/ljishen/my-vim) ####\\n\\n" >> "$HOME"/.profile

function export_envs {
    for env in $1; do
        export "${env?}"
        printf "export %s\\n" "$env" >> "$HOME"/.profile
    done
}

export_envs "TERM=screen-256color"


# Install js-beautify as the JSON Formatter for plugin google/vim-codefmt
# Install bandit, flake8, pycodestyle and pydocstyle as the syntax checkers
#     for Python3 used in plugin vim-syntastic/syntastic
# Install mypy as the syntax checkers for Python3 used in plugin vim-syntastic/syntastic
# pylint is a code linter for Python used by plugin vim-syntastic/syntastic
# ansible-lint is a best-practices linter for Ansible playbooks used by plugin vim-syntastic/syntastic
pip3 install jsbeautifier \
                 flake8 \
                 mypy \
                 bandit \
                 pylint \
                 pycodestyle \
                 pydocstyle \
                 ansible-lint

# Compiling YouCompleteMe(YCM) with semantic support for Java and C-family languages
"$HOME"/.vim/bundle/YouCompleteMe/install.py --clang-completer --java-completer


# Install various checkers for plugin vim-syntastic/syntastic

export_envs "SYNTASTIC_HOME=$HOME/.vim/syntastic"
mkdir -p "$SYNTASTIC_HOME"

# Install Checkstyle (for Java)
export_envs "CHECKSTYLE_VERSION=8.12 \
             CHECKSTYLE_HOME=${SYNTASTIC_HOME}/checkstyle"
mkdir -p "${CHECKSTYLE_HOME}" && \
    curl -fsSL https://github.com/checkstyle/checkstyle/releases/download/checkstyle-"${CHECKSTYLE_VERSION}"/checkstyle-"${CHECKSTYLE_VERSION}"-all.jar -o "${CHECKSTYLE_HOME}"/checkstyle-"${CHECKSTYLE_VERSION}"-all.jar
curl -fsSL https://raw.githubusercontent.com/checkstyle/checkstyle/master/src/main/resources/google_checks.xml -o "${CHECKSTYLE_HOME}"/google_checks.xml
export_envs "CHECKSTYLE_JAR=${CHECKSTYLE_HOME}/checkstyle-${CHECKSTYLE_VERSION}-all.jar \
             CHECKSTYLE_CONFIG=${CHECKSTYLE_HOME}/google_checks.xml"

# Install Checkpatch
export_envs "CHECKPATCH_HOME=${SYNTASTIC_HOME}/checkpatch"
mkdir -p "${CHECKPATCH_HOME}" && \
    curl -fsSL https://raw.githubusercontent.com/torvalds/linux/master/scripts/checkpatch.pl -o "${CHECKPATCH_HOME}"/checkpatch.pl
chmod +x "${CHECKPATCH_HOME}"/checkpatch.pl
PATH="${CHECKPATCH_HOME}:$PATH"

# Install google-java-format
export_envs "GOOGLE_JAVA_FORMAT_VERSION=1.6 \
             GOOGLE_JAVA_FORMAT_HOME=${SYNTASTIC_HOME}/google-java-format"
export_envs "GOOGLE_JAVA_FORMAT_JAR=${GOOGLE_JAVA_FORMAT_HOME}/google-java-format-${GOOGLE_JAVA_FORMAT_VERSION}-all-deps.jar"
mkdir -p "${GOOGLE_JAVA_FORMAT_HOME}" && \
    curl -fsSL https://github.com/google/google-java-format/releases/download/google-java-format-"${GOOGLE_JAVA_FORMAT_VERSION}"/google-java-format-"${GOOGLE_JAVA_FORMAT_VERSION}"-all-deps.jar -o "${GOOGLE_JAVA_FORMAT_JAR}"

# Install hadolint (for Dockerfile)
if [[ $(arch) = x86_64 ]]; then
    export_envs "HADOLINT_VERSION=1.12.0 \
                 HADOLINT_HOME=${SYNTASTIC_HOME}/hadolint"
    mkdir -p "${HADOLINT_HOME}" && \
        curl -fsSL https://github.com/hadolint/hadolint/releases/download/v"${HADOLINT_VERSION}"/hadolint-Linux-x86_64 -o "${HADOLINT_HOME}"/hadolint
    chmod +x "${HADOLINT_HOME}"/hadolint
    PATH="${HADOLINT_HOME}:$PATH"
fi

# Because mypy is installed to the "$HOME"/.local/bin,
#     we need to add it to the PATH if it doesn't already exist
home_local_bin="$HOME"/.local/bin
if [[ :$PATH: != *:"$home_local_bin":* ]] ; then
    PATH="${home_local_bin}:$PATH"
fi

# Finally export the PATH after all the updates on this env
export_envs "PATH=$PATH"

printf "\\n#### END ####" >> "$HOME"/.profile


printf "\\nInstallation completed successfully.\\n"
