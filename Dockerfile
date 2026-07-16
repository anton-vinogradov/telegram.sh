FROM alpine

RUN apk add --no-cache bash curl jq

COPY telegram /usr/local/bin/telegram

ENTRYPOINT ["/usr/local/bin/telegram"]
CMD ["-h"]
