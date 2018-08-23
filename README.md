# xinetd_bash_http_service
An HTTP service for xinetd written in bash

This is written as a starting framework example for servicing HTTP requests to
obtain health of some local service that is desired to be monitored. It can
also be used on the command line to obtain the same health information.

If you need a monitoring application that is heavy in client connections, or
needs to store stateful information, consider writing a daemon that runs on its
own as opposed to an xinetd application. However, if your needs are light, and
you want HTTP REST-like capabilities, perhaps this meets your needs.


## Using for your purposes

Edit the [xinetdhttpservice.sh][] file, modifying the script at the bottom to
add your custom code. Look for the section titled "Add your health checking
logic below". You can modify or remove the example code that is in this
section.

```bash
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
```

[xinetdhttpservice.sh]: https://github.com/rglaue/xinetd_bash_http_service/blob/master/xinetdhttpservice.sh

### Available functions

#### get_http_req_uri_params_value &lt;param-name&gt;
This function will obtain the value of a paramter provided in the HTTP request.
```bash
# if GET Request URI (GET_REQ_URI) is "/?uptime=seconds&format=json"
format_value=$(get_http_req_uri_params_value "format")
# Result: format_value == json
```

#### http_response &lt;http-code&gt; &lt;message&gt;
This function will return a HTTP response and exit.
It will do nothing and return if the --http-response option is not set to 1,
or if the request came from the command line and not as a HTTP request.
```bash
http_response 301 "I did not find what you were looking for."
```

#### decrease_health_value
This function will decrease the global health value
```bash
decrease_health_value
```

#### display_health_value
This function displays the global helath value in a HTTP response or standard
output for the command line, and then exits.
```bash
display_health_value
```


## Runtime parameters

```bash
linux$ xinetdhttpservice.sh --help
xinetd_http_service 0.2
https://github.com/rglaue/xinetd_bash_http_service
Copyright (C) 2018 Russell Glaue, CAIT, WIU <http://www.cait.org>

Usage: xinetd_http_service [options]
Description: bash script called by xinetd to service a HTTP request; a farmework for reporting on health

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
    xinetd_http_service                 # Returns HTTP status
    xinetd_http_service --health-value  # Returns a number based on healthiness
    echo "GET /weight-value?max-weight=200 HTTP/1.1" | xinetd_http_service
```


## Runtime Example Usage

### Test to see how HTTP headers are parsed

#### HTTP GET

```bash
linux$ echo "GET /test123?var1=val1 HTTP/1.0" | xinetdhttpservice.sh --http-status --show-headers
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close
Content-Length: 179

HTTP_REQ_VERSION=HTTP/1.0
HTTP_REQUEST=GET /test123?var1=val1 HTTP/1.0
HTTP_REQ_URI=/test123?var1=val1
HTTP_REQ_URI_PATH=/test123
HTTP_REQ_METHOD=GET
HTTP_REQ_URI_PARAMS=var1=val1
```

#### HTTP POST

```bash
linux$ xinetdhttpservice.sh --show-headers <<HTTP_EOF
POST /weight-value?max-weight=200 HTTP/1.1
User-Agent: noagent/1.0
Host: 127.0.0.1:8080
Accept: */*
Content-Length: 78
Content-Type: application/x-www-form-urlencoded

{
  "type": "json",
  "key": "animal",
  "color": "brown",
  "name": "bear"
}
HTTP_EOF
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close
Content-Length: 515

HTTP_CONTENT_LENGTH=78
HTTP_USER_AGENT=noagent/1.0
HTTP_REQ_VERSION=HTTP/1.1
HTTP_POST_CONTENT={
HTTP_ACCEPT=*/*
HTTP_CONTENT_TYPE=application/x-www-form-urlencoded
HTTP_REQUEST=POST /weight-value?max-weight=200 HTTP/1.1
HTTP_REQ_URI=/weight-value?max-weight=200
HTTP_REQ_URI_PATH=/weight-value
HTTP_REQ_METHOD=POST
HTTP_REQ_URI_PARAMS=max-weight=200
HTTP_SERVER=127.0.0.1:8080
--BEGIN:HTTP_POST_CONTENT--
{
  "type": "json",
  "key": "animal",
  "color": "brown",
  "name": "bear"
}

--END:HTTP_POST_CONTENT--
```

#### HTTP POST Config: MAX_HTTP_POST_LENGTH

At the top of the xinetdhttpservice.sh bash script, there is a global variable
that define the maximum allowed length of posted data. Posted data that has a
length greater than this will be cut off.

```bash
MAX_HTTP_POST_LENGTH=200
```

#### HTTP POST Config: READ_BUFFER_LENGTH

If a non-compliant HTTP client is posting data that is shorter than the
Content-Length, then the READ_BUFFER_LENGTH should be set to 1. By default
this value is the size of the Content-Length, which is more efficient.

```bash
  # If the value of Content-Length is greater than the actual content, then
  # read will timeout and never allow the collection from standard input.
  # This is overcome by reading one character at a time.
  #READ_BUFFER_LENGTH=1
  # If you are sure the value of Content-Length always equals the length of the
  # content, then all of standard input can be read in at one time
  READ_BUFFER_LENGTH=$DATA_LENGTH
```

Note: The maximum length of posted data that is accepted is the Content-Length
or the MAX_HTTP_POST_LENGTH, whichever is shorter. If the HTTP client is
posting data, yet provides a Content-Length of 0, no data will be read in.


### Test the HTTP output

```bash
linux$ echo "GET /test123?var1=val1 HTTP/1.0" | xinetdhttpservice.sh --http-status
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close
Content-Length: 7

Success
```

### Retrieve output from the command line

```bash
linux$ xinetdhttpservice.sh
Success
```

```bash
linux$ echo "GET /weight-value?inverse-weight=0&max-weight=120 HTTP/1.0" | xinetdhttpservice.sh
HTTP/1.1 200 OK
Content-Type: text/plain
Connection: close
Content-Length: 16

WEIGHT_VALUE=119
```

### As an xinetd HTTP service

To configure this script as an xinetd service, add the [xinetdhttpservice_config][]
file to the system /etc/xinetd.d/ directory.

Then restart xinetd
```bash
CentOS-Flavors$ systemctl restart xinetd
```

Then query the service via a HTTP call
```bash
linux$ curl http://0.0.0.0:8080/weight-value?inverse-weight=0&max-weight=120
WEIGHT_VALUE=119
```

[xinetdhttpservice_config]: https://github.com/rglaue/xinetd_bash_http_service/blob/master/xinetdhttpservice_config


## License

Copyright (C) 2018 [Center for the Application of Information Technologies](http://www.cait.org),
[Western Illinois University](http://www.wiu.edu). All rights reserved.

Apache License 2.0, see [LICENSE](https://github.com/prometheus/haproxy_exporter/blob/master/LICENSE).

This program is free software.
