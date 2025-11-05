#!/bin/bash

test_projects=false

while getopts 't' OPTION; do
  case "$OPTION" in
    t)
      echo "[-t] used - each configuration will be tested"
      echo
      test_projects=true
      ;;
    ?)
      echo "script usage: $(basename  $0) [-t]" >&2
      exit 1
      ;;
  esac
done
shift "$(($OPTIND -1))"

cd $(dirname "$0")/../
CodeGenConfigsDirectory="./Tests/TestCodeGenConfigurations"

for dir in `ls $CodeGenConfigsDirectory`;
do
  echo "-- Generating code for project: $dir --"
  (cd apollo-ios-codegen && swift run apollo-ios-cli generate -p ../$CodeGenConfigsDirectory/$dir/apollo-codegen-config.json)
  
  if [ $? -ne 0 ]; then
    echo "Error: Code generation failed for $dir"
    exit 1
  fi

  if [ "$test_projects" = true ]
  then
    echo -e "-- Testing project: $dir --"
    cd $CodeGenConfigsDirectory/$dir

    /bin/bash ./test-project.sh
    test_exit_code=$?
    
    cd - > /dev/null
    
    if [ $test_exit_code -ne 0 ]; then
      echo "Error: Test failed for $dir"
      exit 1
    fi
    
    echo -e "\n"
  fi
done
