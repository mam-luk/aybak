FROM islamicnetwork/php:8.2-cli

COPY . /ip-extractor/

RUN cd /ip-extractor/ && composer install --no-dev

RUN mkdir -p /root/.ssh && \
    ssh-keyscan -H github.com >> /root/.ssh/known_hosts && \
    chmod 777 -R /ip-extractor/.ssh

ENV GIT_SSH_COMMAND "ssh -i /ip-extractor/.ssh/id_rsa"

CMD ["php", "/ip-extractor/bin/aybak"]
