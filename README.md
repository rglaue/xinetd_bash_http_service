# xinetd_bash_http_service
An HTTP service for xinetd written in bash

This is written as a starting framework example for servicing HTTP requests to
obtain health of some local service that is desired to be monitored. It can
also be used on the command line to obtain the same health information.

If you need a monitoring application that is heavy in client connections, or
needs to store stateful information, consider writing a daemon that runs on its
own as opposed to an xinetd application. However, if your needs are light, and
you want HTTP REST-like capabilities, perhaps this meets your needs.



## Runtime parameters

```bash
linux$ xinetdhttpservice.sh --help
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

To configure this script as an xinetd service, add the
[xinetdhttpservice_config]: xinetdhttpservice_config
file to the system /etc/xinetd.d/ directory.

Then restart xinetd
```bash
CentOS-Flavors$ systemctl restart xinetd
```

Then query the service via an HTTP call
```bash
linux$ curl http://0.0.0.0:8080/weight-value?inverse-weight=0&max-weight=120
WEIGHT_VALUE=119
```

## License

Apache License 2.0, see [LICENSE](https://github.com/prometheus/haproxy_exporter/blob/master/LICENSE).
