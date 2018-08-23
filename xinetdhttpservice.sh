#!/bin/bash

#
# xinetdhttpservice
#

PROG=xinetd_http_service
DESCRIPTION="bash script called by xinetd to service a HTTP request; a farmework for reporting on health"
SYNOPSIS="${PROG} [options]"
VERSION=0.2
LASTMOD=20180822
MAX_HTTP_POST_LENGTH=200

#
# Handle the program's usage documentation
#
print_usage () {
    echo "Usage: ${SYNOPSIS}"
    echo "Description: ${DESCRIPTION}"
}

print_help ()  {
    print_version
    echo
    print_usage
    cat << EOF

Options:
    -h, --help        show this help message and exit
    --version         show program's version number and exit
    --verbose         Display verbose messages
    --http-status     returns HTTP status for healthiness
                       when called by command line, default is --http-status=0
    --health-value    Show a value consistent with the health of this node
                       100% healthy is 0, value decreases with health status
    --weight-value    Show a weighted value based on the health value
    --max-weight=n    Start with this weight as max, default=100
    --inverse-weight  Inverse the weighted value
    --show-headers    Show the parsed HTTP headers instead of displaying health
    --                Optional, specifically ends reading of options
Examples:
    ${PROG}                 # Returns HTTP status
    ${PROG} --health-value  # Returns a number based on healthiness
    echo "GET /weight-value?max-weight=200 HTTP/1.1" | ${PROG}
EOF
}

print_version () {
    echo "$PROG $VERSION"
    echo "https://github.com/rglaue/xinetd_bash_http_service"
    echo "Copyright (C) 2018 Russell Glaue, CAIT, WIU <http://www.cait.org>"
}

#
# Parse parameters
#

# Set the default values before parsing the parameters
: ${VERBOSE:=0}
: ${OPT_HTTP_STATUS:=0}
: ${OPT_HEALTH_VALUE:=0}
: ${OPT_WEIGHT_VALUE:=0}
: ${OPT_INVERSE_WEIGHT:=0}
: ${OPT_SHOW_HEADERS:=0}

#
# Parse parameters from the command line 
#
OPTS=`getopt -o ho:v --long help,version,verbose,http-status,health-value,weight-value,max-weight:,inverse-weight,show-headers \
    -n '${PROG}' -- "$@"`
if [ $? != 0 ] ; then
    print_usage
    exit 1
fi

eval set -- "$OPTS"

while true ; do
    case "$1" in
        -h|--help) print_help; exit ;;
        --version) print_version; exit ;;
        -v|--verbose) let VERBOSE++ ; shift ;;

        --http-status)    OPT_HTTP_STATUS=1;  shift ;;
        --health-value)   OPT_HEALTH_VALUE=1; shift ;;

        --weight-value)   OPT_WEIGHT_VALUE=1; shift ;;
        --max-weight)     
                      if [[ $2 =~ ^[0-9]+$ ]]; then
                        MAX_WEIGHT_VALUE=$2;
                      elif [ -n "$2" ] && [[ ! $2 =~ ^[0-9]+$ ]]; then
                       	echo "Error: --max-weight requires a numerical value"
                       	exit 1
                      fi
                      shift 2 ;;
        --inverse-weight) OPT_INVERSE_WEIGHT=1; shift ;;
        --show-headers)   OPT_SHOW_HEADERS=1;   shift ;;

        --) shift; break;;
        *) break ;;
    esac
done

#
# Read the HTTP headers from standard input, and parse and store their
# values in environment variables.
#
while read -t 0.01 line; do
    line=${line//$'\r'}
    if [ $VERBOSE -ge 1 ]; then
      echo "H: $line"
    fi
    if [ -z "$line" ]; then break; fi
    if echo "${line}" | grep -qi "^GET\|POST\|PUT\|DELETE"; then
      # GET /test123?r=123 HTTP/1.1
      export HTTP_REQUEST="${line}"
      export HTTP_REQ_METHOD="$(echo "${line}"|cut -d" " -f 1)"
      export HTTP_REQ_URI="$(echo "${line}"|cut -d" " -f 2)"
      export HTTP_REQ_URI_PATH="$(echo "${HTTP_REQ_URI}"|cut -d"?" -f 1)"
      if echo "$HTTP_REQ_URI"|grep -q '?'; then
        export HTTP_REQ_URI_PARAMS="$(echo "${HTTP_REQ_URI}"|cut -d"?" -f 2-)"
      else
	export HTTP_REQ_URI_PARAMS=""
      fi
      export HTTP_REQ_VERSION="$(echo "${line}"|cut -d" " -f 3-)"
    elif echo "${line}" | grep -qi "^User-Agent:"; then
      # User-Agent: curl/7.29.0
      export HTTP_USER_AGENT="$(echo "${line}"|cut -d" " -f 2-)"
    elif echo "${line}" | grep -qi "^Host:"; then
      # Host: 0.0.0.0:8081
      export HTTP_SERVER="$(echo "${line}"|cut -d" " -f 2-)"
    elif echo "${line}" | grep -qi "^Accept:"; then
      # Accept: */*
      export HTTP_ACCEPT="$(echo "${line}"|cut -d" " -f 2-)"
      #continue
    elif echo "${line}" | grep -qi "^Content-Length:"; then
      # Content-Length: 5
      export HTTP_CONTENT_LENGTH="$(echo "${line}"|cut -d" " -f 2-)"
    elif echo "${line}" | grep -qi "^Content-Type:"; then
      # Content-Type: application/x-www-form-urlencoded
      export HTTP_CONTENT_TYPE="$(echo "${line}"|cut -d" " -f 2-)"
    elif [ ${#line} -ge 1 ]; then
      # <any header>
      continue
    else
      break
      #continue
    fi
done

#
# Read the HTTP POST data from standard input
# This does not support a Content-type of multipart/mixed
# This does not support chunking. It expects, and only allows, posted data to
#   be the size of the Content-Length.
#
if [ "${HTTP_REQ_METHOD}" == "POST" ] && [ ${HTTP_CONTENT_LENGTH} -ge 1 ]; then
  export HTTP_POST_CONTENT=""
  DATA_LENGTH=$HTTP_CONTENT_LENGTH
  if [ ${DATA_LENGTH} -gt ${MAX_HTTP_POST_LENGTH} ]; then
    DATA_LENGTH=$MAX_HTTP_POST_LENGTH
  fi
  # If the value of Content-Length is greater than the actual content, then
  # read will timeout and never allow the collection from standard input.
  # This is overcome by reading one character at a time.
  #READ_BUFFER_LENGTH=1
  # If you are sure the value of Content-Length always equals the length of the
  # content, then all of standard input can be read in at one time
  READ_BUFFER_LENGTH=$DATA_LENGTH
  #
  # Read POST data via standard input
  while IFS= read -N $READ_BUFFER_LENGTH -r -t 0.01 post_buffer; do
    let "DATA_LENGTH = DATA_LENGTH - READ_BUFFER_LENGTH"
    HTTP_POST_CONTENT="${HTTP_POST_CONTENT}${post_buffer}"
    # Stop reading if we reach the content length, max length, or expected length
    if [ ${#HTTP_POST_CONTENT} -ge ${HTTP_CONTENT_LENGTH} ]; then
      break;
    elif [ ${#HTTP_POST_CONTENT} -ge ${MAX_HTTP_POST_LENGTH} ]; then
      break;
    elif [ ${DATA_LENGTH} -le 0 ]; then
      break;
    fi
  done
  if [ $VERBOSE -ge 1 ]; then
    echo -e "D: $HTTP_POST_CONTENT"
  fi
fi

#
# A function to parse HTTP_REQ_URI_PARAMS and return the value of a given
# parameter name
# Example:
#   param_value=$(get_http_req_uri_params_value "param_name")
#   if [ "$?" -eq 1 ]; then echo "param_name" not provided; fi
#
get_http_req_uri_params_value () {
    # Example: "a=123&b=456&c&d=789"
    PARAM_NAME=$1
    IFS='&' read -r -a params <<< "$HTTP_REQ_URI_PARAMS"
    for element in "${params[@]}"; do
      element_name="$(echo "$element" | cut -d"=" -f 1)"
      if [ "$element_name" == "$PARAM_NAME" ]; then
        if echo "$element" | grep -q "="; then
          element_value="$(echo "$element" | cut -d"=" -f 2-)"
          echo "$element_value"
        else
          echo ""
        fi
        exit 0
      fi
    done
    exit 1
}

#
# Parse parameters from the HTTP request
#
if echo ${HTTP_REQ_URI_PATH} | grep -qi "health-value"; then
  OPT_HTTP_STATUS=1
  OPT_HEALTH_VALUE=1
elif echo ${HTTP_REQ_URI_PATH} | grep -qi "weight-value"; then
  OPT_HTTP_STATUS=1
  OPT_WEIGHT_VALUE=1
  if echo ${HTTP_REQ_URI_PARAMS} | grep -qi "inverse-weight=1"; then
    OPT_INVERSE_WEIGHT=1
  elif echo ${HTTP_REQ_URI_PARAMS} | grep -qi "inverse-weight=0"; then
    OPT_INVERSE_WEIGHT=0
  fi
  if echo ${HTTP_REQ_URI_PARAMS} | grep -qi "max-weight="; then
    MAX_WEIGHT_VALUE=$(get_http_req_uri_params_value "max-weight")
  fi
fi

# Set default values if not defined from prameters
: ${MAX_WEIGHT_VALUE:=100}
# Start with 0, and decrease from here.
HEALTH_VALUE=0

#
# The HTTP response. This will return a HTTP response with the provided HTTP
#   code and a descriptive message.
# Example:
#   http_response 301 "You accessed something that does not exist"
#   http_response 200 '{ "status": "success" }'
#
http_response () {
    HTTP_CODE=$1
    MESSAGE=${2:-Message Undefined}
    length=${#MESSAGE}
  if [ $OPT_HTTP_STATUS -eq 1 ]; then
    if [ "$HTTP_CODE" -eq 503 ]; then
      echo -en "HTTP/1.1 503 Service Unavailable\r\n" 
    elif [ "$HTTP_CODE" -eq 301 ]; then
      echo -en "HTTP/1.1 301 Not Found\r\n" 
    elif [ "$HTTP_CODE" -eq 200 ]; then
      echo -en "HTTP/1.1 200 OK\r\n" 
    else
      echo -en "HTTP/1.1 ${HTTP_CODE} UNKNOWN\r\n" 
    fi
    echo -en "Content-Type: text/plain\r\n" 
    echo -en "Connection: close\r\n" 
    echo -en "Content-Length: ${length}\r\n" 
    echo -en "\r\n" 
    echo -en "$MESSAGE"
    echo -en "\r\n" 
    sleep 0.1
    exit 0
  fi
}

#
# functions to compute a weight based on a health value
#
# decrease_health_value - decreases the global health value
# Example:
#   decrease_health_value
decrease_health_value () {
    let HEALTH_VALUE--
}

# displays the global helath value in a HTTP response or standard output for
#   the command line, and then exits.
# Example:
#   display_health_value
display_health_value () {
    if [ $OPT_HEALTH_VALUE -eq 1 ]; then
      http_response 200 "HEALTH_VALUE=$HEALTH_VALUE"
      echo "$HEALTH_VALUE"
      exit 0
    fi
    if [ $OPT_WEIGHT_VALUE -eq 1 ]; then
      MY_WEIGHT="$(expr $MAX_WEIGHT_VALUE + $HEALTH_VALUE)"
      if [ $OPT_INVERSE_WEIGHT -eq 1 ]; then
        MY_INVERSE_WEIGHT="$(expr $MAX_WEIGHT_VALUE - $MY_WEIGHT)"
        http_response 200 "WEIGHT_VALUE=${MY_INVERSE_WEIGHT}"
        echo ${MY_INVERSE_WEIGHT}
      else
        http_response 200 "WEIGHT_VALUE=${MY_WEIGHT}"
        echo ${MY_WEIGHT}
      fi
      exit 0
    fi
    if [ $HEALTH_VALUE -eq 0 ]; then
      http_response 200 "Service OK"
      echo "Service OK"
      exit 0
    else
      http_response 503 "Service Unhealthy"
      echo "Service Unhealthy"
      exit 0
    fi
}

#
# --show-headers
# Show the HTTP headers as parsed into the environment variables
#
if [ $OPT_SHOW_HEADERS -eq 1 ]; then
    THIS_HEADERS="$(env | grep '^HTTP')"
    if [ ! -z "$HTTP_POST_CONTENT" ]; then
      THIS_HEADERS="${THIS_HEADERS}\n--BEGIN:HTTP_POST_CONTENT--\n${HTTP_POST_CONTENT}\n--END:HTTP_POST_CONTENT--\n"
    fi
    if echo $THIS_HEADERS | grep -q '^HTTP'; then
      http_response 200 "$THIS_HEADERS"
    else
      http_response 200 "No HTTP headers were parsed."
    fi
fi


#
# Add your health checking logic below
#
# If --http-status is provided, http_response() function will send the value in
# an HTTP response. Otherwise the value is displayed alone.
#

# If something unhealthy was detected, then:
decrease_health_value

# display health value response, and exit
display_health_value

# send a http_response of 200
http_response 200 "Success"

# End of program
