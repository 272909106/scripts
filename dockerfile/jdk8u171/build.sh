set -ex
build_name=saas-ops-cn-north-1.jcr.service.jdcloud.com/pro/jdk:8u171
docker build -t $build_name . -f dockerfile-jdk8u171
docker push $build_name
