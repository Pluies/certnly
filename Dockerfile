FROM debian
RUN apt-get update -y \
 && apt-get install -y python certbot curl \
 && mkdir /opt/certnly
WORKDIR /opt/certnly
ADD certnly.sh certnly.sh
CMD ./certnly.sh
