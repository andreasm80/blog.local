#!/bin/bash
EDITOR=typora
GREEN=$(tput -T screen setaf 2)
NORMAL=$(tput sgr0)

if [[ $1 = "story" ]]; then
	#statements
	## Usage
	# `new STORY TITLE-with-dashes`
	# `new story section section-name`

	if [[ $2 = 'section' ]]; then
		hugo new story/"$3"/_index.md
		open content/story/"$3"/
		else
			export STORY=$2
			export SLUG=$3
			DATE=`date "+%Y-%m-%d"`

			hugo new story/$STORY/$DATE-$SLUG/index.md

			export DESTINATION="content/story/$STORY/$DATE-$SLUG"

			mkdir -p $DESTINATION/images/;

			open $DESTINATION/; $EDITOR $DESTINATION/; cd $DESTINATION/;

			printf "\n$DESTINATION\n";
	fi

fi

if [[ $1 = "post" ]]; then
	#statements
	# POSTS
	export SLUG=$2
	DATE=`date "+%Y-%m-%d"`

	hugo new posts/$DATE-$SLUG/index.md

	mkdir -p content/posts/$DATE-$SLUG/images/;

	open content/posts/$DATE-$SLUG/; $EDITOR content/posts/$DATE-$SLUG/; cd content/posts/$DATE-$SLUG/;
fi

# I think Hugo now does this on it's own.
#if [[ $1 = 'undraft' ]]; then
#	DATE=`date "+%FT%TZ"`
#
#	gsed -i "s/date:.*$/date: ${DATE}/g" $2;
#	gsed -i "/draft: true/d" $2;
#fi

if [[ $1 = 'help' ]]; then
	#statements
	echo "${GREEN}post : ${NORMAL}creates a new post, sintax is :: new.sh post TITLE-with-dashes"
	echo "${GREEN}story : ${NORMAL}creates a new post inside a story, sintax is ::  new.sh story STORY-NAME TITLE-with-dashes"
fi
