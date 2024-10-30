#!/usr/bin/env bash

# Copyright 2018 The KubeSphere Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


CurrentDIR=$(cd "$(dirname "$0")" || exit;pwd)
ImagesDirDefault=${CurrentDIR}/kubesphere-images
save="false"
registryurl=""
reposUrl=("quay.azk8s.cn" "gcr.azk8s.cn" "docker.elastic.co" "quay.io" "k8s.gcr.io")
KUBERNETES_VERSION=${KUBERNETES_VERSION:-"v1.21.5"}
HELM_VERSION=${HELM_VERSION:-"v3.6.3"}
CNI_VERSION=${CNI_VERSION:-"v0.9.1"}
ETCD_VERSION=${ETCD_VERSION:-"v3.4.13"}
CRICTL_VERSION=${CRICTL_VERSION:-"v1.22.0"}
DOCKER_VERSION=${DOCKER_VERSION:-"20.10.8"}

func() {
    echo "Usage:"
    echo
    echo "  $0 [-l IMAGES-LIST] [-d IMAGES-DIR] [-r PRIVATE-REGISTRY] [-v KUBERNETES_VERSION ]"
    echo
    echo "Description:"
    echo "  -b                     : save kubernetes' binaries."
    echo "  -d IMAGES-DIR          : the dir of files (tar.gz) which generated by \`docker save\`. default: ${ImagesDirDefault}"
    echo "  -l IMAGES-LIST         : text file with list of images."
    echo "  -r PRIVATE-REGISTRY    : target private registry:port."
    echo "  -s                     : save model will be applied. Pull the images in the IMAGES-LIST and save images as a tar.gz file."
    echo "  -v KUBERNETES_VERSION  : download kubernetes' binaries. default: v1.21.5"
    echo "  -h                     : usage message"
    echo
    echo "Examples:"
    echo
    echo "# Download the default kubernetes version dependency binaries.(default: [kubernetes: v1.21.5], [helm: v3.6.3], [cni: v0.9.1], [etcd: v3.4.13])"
    echo "./offline-installtion-tool.sh -b"
    echo
    echo "# Custom download the kubernetes version dependecy binaries."
    echo "export KUBERNETES_VERSION=v1.22.1;export HELM_VERSION=v3.6.3;"
    echo "./offline-installtion-tool.sh -b"
    exit
}

while getopts 'bsl:r:d:v:h' OPT; do
    case $OPT in
        b) binary="true";;
        d) ImagesDir="$OPTARG";;
        l) ImagesList="$OPTARG";;
        r) Registry="$OPTARG";;
        s) save="true";;
        v) KUBERNETES_VERSION="$OPTARG";;
        h) func;;
        ?) func;;
        *) func;;
    esac
done

if [ -z "${ImagesDir}" ]; then
    ImagesDir=${ImagesDirDefault}
fi

if [ -n "${Registry}" ]; then
   registryurl=${Registry}
fi

if [ -z "${ARCH}" ]; then
  case "$(uname -m)" in
  x86_64)
    ARCH=amd64
    ;;
  armv8*)
    ARCH=arm64
    ;;
  aarch64*)
    ARCH=arm64
    ;;
  armv*)
    ARCH=armv7
    ;;
  *)
    echo "${ARCH}, isn't supported"
    exit 1
    ;;
  esac
fi

binariesDIR=${CurrentDIR}/kubekey/${KUBERNETES_VERSION}/${ARCH}

if [[ ${binary} == "true" ]]; then
  mkdir -p ${binariesDIR}
  if [ -n "${KKZONE}" ] && [ "x${KKZONE}" == "xcn" ]; then
     echo "Download kubeadm ..."
     curl -L -o ${binariesDIR}/kubeadm https://kubernetes-release.pek3b.qingstor.com/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubeadm
     echo "Download kubelet ..."
     curl -L -o ${binariesDIR}/kubelet https://kubernetes-release.pek3b.qingstor.com/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubelet
     echo "Download kubectl ..."
     curl -L -o ${binariesDIR}/kubectl https://kubernetes-release.pek3b.qingstor.com/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl
     echo "Download helm ..."
     curl -L -o ${binariesDIR}/helm https://kubernetes-helm.pek3b.qingstor.com/linux-${ARCH}/${HELM_VERSION}/helm
     echo "Download cni plugins ..."
     curl -L -o ${binariesDIR}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz https://containernetworking.pek3b.qingstor.com/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz
     echo "Download etcd ..."
     curl -L -o ${binariesDIR}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz https://kubernetes-release.pek3b.qingstor.com/etcd/release/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz
     echo "Download crictl ..."
     curl -L -o ${binariesDIR}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz https://kubernetes-release.pek3b.qingstor.com/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz
     echo "Download docker ..."
     curl -L -o ${binariesDIR}/docker-${DOCKER_VERSION}.tgz https://mirrors.aliyun.com/docker-ce/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz
  else
     echo "Download kubeadm ..."
     curl -L -o ${binariesDIR}/kubeadm https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubeadm
     echo "Download kubelet ..."
     curl -L -o ${binariesDIR}/kubelet https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubelet
     echo "Download kubectl ..."
     curl -L -o ${binariesDIR}/kubectl https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl
     echo "Download helm ..."
     curl -L -o ${binariesDIR}/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz && cd ${binariesDIR} && tar -zxf helm-${HELM_VERSION}-linux-${ARCH}.tar.gz && mv linux-${ARCH}/helm . && rm -rf *linux-${ARCH}* && cd -
     echo "Download cni plugins ..."
     curl -L -o ${binariesDIR}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz
     echo "Download etcd ..."
     curl -L -o ${binariesDIR}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz
     echo "Download crictl ..."
     curl -L -o ${binariesDIR}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz
     echo "Download docker ..."
     curl -L -o ${binariesDIR}/docker-${DOCKER_VERSION}.tgz https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz
  fi
fi

if [[ ${save} == "true" ]] && [[ -n "${ImagesList}" ]]; then
    if [ ! -d ${ImagesDir} ]; then
       mkdir -p ${ImagesDir}
    fi
    ImagesListLen=$(cat ${ImagesList} | wc -l)
    name=""
    images=""
    index=0
    for image in $(<${ImagesList}); do
        if [[ ${image} =~ ^\#\#.* ]]; then
           if [[ -n ${images} ]]; then
              echo ""
              echo "Save images: "${name}" to "${ImagesDir}"/"${name}".tar.gz  <<<"
              nerdctl save ${images} | gzip -c > ${ImagesDir}"/"${name}.tar.gz
              echo ""
           fi
           images=""
           name=$(echo "${image}" | sed 's/#//g' | sed -e 's/[[:space:]]//g')
           ((index++))
           continue
        fi

        image=$(echo "${image}" |tr -d '\r')
        nerdctl pull "${image}"
        images=${images}" "${image}

        if [[ ${index} -eq ${ImagesListLen}-1 ]]; then
           if [[ -n ${images} ]]; then
              nerdctl save ${images} | gzip -c > ${ImagesDir}"/"${name}.tar.gz
           fi
        fi
        ((index++))
    done
elif [ -n "${ImagesList}" ]; then
    # shellcheck disable=SC2045
    for image in $(ls ${ImagesDir}/*.tar.gz); do
      echo "Load images: "${image}"  <<<"
      nerdctl load  < $image
    done

    if [[ -n ${registryurl} ]]; then
       for image in $(<${ImagesList}); do
          if [[ ${image} =~ ^\#\#.* ]]; then
             continue
          fi
          url=${image%%/*}
          ImageName=${image#*/}
          echo $image

          if echo "${reposUrl[@]}" | grep -Fx "$url" &>/dev/null; then
            imageurl=$registryurl"/"${image#*/}
          elif [ $url == $registryurl ]; then
              if [[ $ImageName != */* ]]; then
                 imageurl=$registryurl"/library/"$ImageName
              else
                 imageurl=$image
              fi
          elif [ "$(echo $url | grep ':')" != "" ]; then
              imageurl=$registryurl"/library/"$image
          else
              imageurl=$registryurl"/"$image
          fi

          ## push image
          image=$(echo "${image}" |tr -d '\r')
          imageurl=$(echo "${imageurl}" |tr -d '\r')
          echo $imageurl
          nerdctl tag $image $imageurl
          nerdctl push $imageurl
       done
    fi
fi

