Name
exist_auto_install
====

Overview

## Description
[nict-csl/exist](https://github.com/nict-csl/exist) の構築を楽にするためのスクリプトとなります.

## Requirement
- CentOS Linux release 7.9.2009 (Core)
- kernel-ml-5.9.8-1 (なるべく最新版がよろしいかと)
- Python3.6.12 (3.7.x以上は、requirements.txtで指定されているVersionにひっかかります)

## Usage
- 上記の要件を満たしてGithubからスクリプトDL && 実行すればOKです.
```
# git clone https://github.com/r4sd/exist_auto_install.git
# cd exist_auto_install/
# . exist_install.sh

# 
# service start exist.service
```
