import inspect
import json
import logging
import threading
import time
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Type, TypeVar
import re

import boto3
from awscli.customizations.eks.get_token import (
    TOKEN_EXPIRATION_MINS,
    STSClientFactory,
    TokenGenerator,
)
from kubernetes import client as k8s_client
from kubernetes.client.rest import ApiException
from kubernetes.stream import stream

logger = logging.getLogger(__name__)

# Type variable for the Kubernetes API client classes
T = TypeVar("T")

class Token:
    __token: str = None
    __expiration: datetime = None

    def __init__(self) -> None:
        self._lock = threading.RLock()

    def is_expired(self) -> bool:
        with self._lock:
            return datetime.now(timezone.utc) >= self.__expiration

    @property
    def token(self) -> str:
        with self._lock:
            return self.__token

    @token.setter
    def token(self, val: str) -> None:
        with self._lock:
            self.__token = val

    @property
    def expiration(self) -> datetime:
        with self._lock:
            return self.__expiration

    @expiration.setter
    def expiration(self, val: datetime) -> None:
        with self._lock:
            self.__expiration = val

    def __repr__(self):
        return f"Token(token={self.token}, expiration={self.expiration})"

class EKSClient:
    TOKEN_EXPIRATION_BUFFER_SECONDS = 60

    def __init__(self, cluster_name) -> None:
        """
        Initialize the client. Using the provided cluster name we will use the EKS API to look up the
        endpoint for the cluster, so that we can then generate a client.

        Args:
            cluster_name: the name of the cluster that we will work with
        """
        self._cluster_name = cluster_name
        self._eks_client = boto3.client("eks")
        self._cluster_endpoint = self._get_cluster_endpoint()
        self._client_cache: Dict[T, Any] = {}

        # Let's start by creating the STS client
        sess = boto3.Session()
        self._sts_client = STSClientFactory(sess._session).get_sts_client()
        self._token_generator = TokenGenerator(self._sts_client)
        self._token = Token()

        logger.info(f"Initialized new {__name__} for {self._cluster_name}")

        # Start the token refresh thread
        self._refresh_token()
        self._start_token_refresh()

        # Initialize the Kubernetes configuration
        try:
            self._k8s_configuration = k8s_client.Configuration()
            self._k8s_configuration.host = self.endpoint
            self._k8s_configuration.verify_ssl = False
            self._k8s_configuration.assert_hostname = True

            self._update_kube_authz()
            self._start_kube_authz_refresh()

            k8s_client.Configuration.set_default(self._k8s_configuration)
            self.core_v1_api = self.make_kube_client(k8s_client.CoreV1Api)
        except Exception as e:
            logger.error(f"Failed to initialize Kubernetes configuration: {str(e)}")
            raise

    def _get_cluster_endpoint(self) -> str:
        """
        Get the cluster endpoint URL

        Returns:
            str: The cluster endpoint URL
        """
        try:
            resp = self._eks_client.describe_cluster(name=self._cluster_name)
            endpoint = resp["cluster"]["endpoint"]
            logger.info(f"Discovered endpoint {endpoint} for cluster {self._cluster_name}")
            return endpoint
        except self._eks_client.exceptions.ResourceNotFoundException as e:
            logger.error(f"Cluster {self._cluster_name} not found: {str(e)}")
            raise
        except self._eks_client.exceptions.ClientError as e:
            logger.error(f"Failed to describe cluster {self._cluster_name}: {str(e)}")
            raise

    @property
    def endpoint(self) -> str:
        return self._cluster_endpoint

    def _refresh_token(self) -> None:
        """Refresh both token and expiration timestamp"""
        logger.info(f"Refreshing token for cluster {self._cluster_name}")
        tok = self._token_generator.get_token(self._cluster_name)
        exp = datetime.now(timezone.utc) + timedelta(minutes=TOKEN_EXPIRATION_MINS)
        self._token.token = tok
        self._token.expiration = exp
        logger.info(f"Token refreshed: {self._token}")

    def _start_token_refresh(self) -> None:
        """Start a background thread to periodically refresh the token"""
        def refresh_loop():
            while True:
                try:
                    logger.info(f"Token refresh loop for cluster {self._cluster_name}")
                    seconds_until_expire = (
                        self._token.expiration - datetime.now(timezone.utc)
                    ).total_seconds()
                    if seconds_until_expire < self.TOKEN_EXPIRATION_BUFFER_SECONDS:
                        logger.info(f"Token will expire in {seconds_until_expire} seconds, refreshing immediately")
                        self._refresh_token()
                    time.sleep(10)
                except Exception as e:
                    logger.error(f"Error in token refresh loop: {str(e)}")
                    time.sleep(5)

        thread = threading.Thread(target=refresh_loop, daemon=True)
        thread.start()
        logger.info("Token refresh thread started")

    def _update_kube_authz(self) -> None:
        """Update the Kubernetes client authorization header"""
        tok = self._token.token
        self._k8s_configuration.api_key["authorization"] = f"Bearer {tok}"

    def _start_kube_authz_refresh(self) -> None:
        """Start a background thread to periodically refresh the Kubernetes authorization"""
        def refresh_loop():
            while True:
                try:
                    logger.info(f"Kube authz refresh loop for cluster {self._cluster_name}")
                    seconds_until_expire = (
                        self._token.expiration - datetime.now(timezone.utc)
                    ).total_seconds()
                    if seconds_until_expire < self.TOKEN_EXPIRATION_BUFFER_SECONDS:
                        logger.info(f"Token will expire in {seconds_until_expire} seconds, refreshing immediately")
                        self._update_kube_authz()
                    time.sleep(10)
                except Exception as e:
                    logger.error(f"Error in kube authz refresh loop: {str(e)}")
                    time.sleep(5)

        thread = threading.Thread(target=refresh_loop, daemon=True)
        thread.start()
        logger.info("Kube authz refresh thread started")

    def make_kube_client(self, api_cls: Type[T]) -> T:
        """
        Create a Kubernetes client of the specified type

        Args:
            api_cls: The Kubernetes API client class to create

        Returns:
            An instance of the specified client class
        """
        if api_cls in self._client_cache:
            return self._client_cache[api_cls]

        if (not inspect.isclass(api_cls) or
            not hasattr(api_cls, "__module__") or
            not api_cls.__module__.startswith("kubernetes.client")):
            raise ValueError(f"Invalid Kubernetes API client class: {api_cls}")

        try:
            instance = api_cls()
            self._client_cache[api_cls] = instance
            return instance
        except Exception as e:
            logger.error(f"Failed to create client of type {api_cls.__name__}: {str(e)}")
            raise

    def find_pod_by_pattern(self, namespace: str, name_pattern: str) -> str:
        """
        Find a pod in the namespace matching the given pattern

        Args:
            namespace: The namespace to search in
            name_pattern: Pattern to match against pod names

        Returns:
            str: Name of the first matching pod

        Raises:
            Exception: If no matching pod is found or on API errors
        """
        try:
            pods = self.core_v1_api.list_namespaced_pod(namespace=namespace)

            for pod in pods.items:
                if re.search(name_pattern, pod.metadata.name):
                    logger.info(f"Found matching pod: {pod.metadata.name}")
                    return pod.metadata.name

            raise ValueError(f"No pod found matching pattern '{name_pattern}' in namespace '{namespace}'")

        except ApiException as e:
            logger.error(f"Kubernetes API error while finding pod: {str(e)}")
            raise Exception(f"Kubernetes API error: {e}")

    def create_heap_dump(self, namespace: str, pod_name: str, container_name: Optional[str] = None,
                         output_path: str = "/tmp/heapdump.hprof") -> str:
        """
        Create a heap dump from a Java application running in a pod
        """
        try:
            if any(char in pod_name for char in ['*', '?', '[']):
                matched_pod = self.find_pod_by_pattern(namespace, pod_name)
                logger.info(f"Using matched pod: {matched_pod}")
                pod_name = matched_pod

            if not container_name:
                pod = self.core_v1_api.read_namespaced_pod(
                    name=pod_name,
                    namespace=namespace
                )
                if len(pod.spec.containers) > 0:
                    container_name = pod.spec.containers[0].name
                    logger.info(f"Using container: {container_name}")
                else:
                    raise ValueError("No containers found in pod")

            exec_command = [
                '/bin/sh',
                '-c',
                (f'if command -v jcmd >/dev/null 2>&1; then '
                 f'PID=$(jcmd | grep -v jcmd | cut -d" " -f1); '
                 f'jcmd $PID GC.heap_dump {output_path}; '
                 f'elif command -v jmap >/dev/null 2>&1; then '
                 f'PID=$(ps -ef | grep java | grep -v grep | awk \'{{print $2}}\'); '
                 f'jmap -dump:format=b,file={output_path} $PID; '
                 f'else echo "Neither jcmd nor jmap found"; exit 1; '
                 f'fi; '
                 f'echo "Heap dump created at {output_path}"; '
                 f'ls -l {output_path}')
            ]

            logger.info(f"Executing heap dump command in pod {pod_name}, container {container_name}")

            resp = stream(
                self.core_v1_api.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                container=container_name,
                command=exec_command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False
            )

            if "Heap dump created at" in resp:
                logger.info("Successfully created heap dump")
                return output_path
            else:
                logger.error(f"Failed to create heap dump. Output: {resp}")
                raise Exception("Failed to create heap dump")

        except ApiException as e:
            logger.error(f"Kubernetes API error in create_heap_dump: {str(e)}")
            raise Exception(f"Kubernetes API error: {e}")
        except ValueError as e:
            logger.error(f"Value error in create_heap_dump: {str(e)}")
            raise Exception(f"Value error: {e}")
        except Exception as e:
            logger.error(f"Unexpected error in create_heap_dump: {str(e)}")
            raise Exception(f"Unexpected error while creating heap dump: {e}")

    def copy_file_from_pod(self, namespace: str, pod_name: str, src_path: str,
                           dest_path: str, container_name: Optional[str] = None) -> None:
        """
        Copy a file from a pod to the local filesystem
        """
        try:
            exec_command = ['cat', src_path]
            resp = stream(
                self.core_v1_api.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                container=container_name,
                command=exec_command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False
            )

            with open(dest_path, 'wb') as f:
                f.write(resp.encode('utf-8'))

            logger.info(f"Successfully copied file from {src_path} to {dest_path}")

        except ApiException as e:
            logger.error(f"Kubernetes API error in copy_file_from_pod: {str(e)}")
            raise Exception(f"Kubernetes API error: {e}")
        except Exception as e:
            logger.error(f"Unexpected error in copy_file_from_pod: {str(e)}")
            raise Exception(f"Unexpected error while copying file from pod: {e}")

    def get_thread_dump(self, namespace: str, pod_name: str, container_name: str = None) -> str:
        """
        Get a thread dump from a Java application running in a pod
        """
        try:
            if any(char in pod_name for char in ['*', '?', '[']):
                matched_pod = self.find_pod_by_pattern(namespace, pod_name)
                logger.info(f"Using matched pod: {matched_pod}")
                pod_name = matched_pod

            if not container_name:
                pod = self.core_v1_api.read_namespaced_pod(
                    name=pod_name,
                    namespace=namespace
                )
                if len(pod.spec.containers) > 0:
                    container_name = pod.spec.containers[0].name
                    logger.info(f"Using container: {container_name}")
                else:
                    raise ValueError("No containers found in pod")

            exec_command = [
                '/bin/sh',
                '-c',
                ('if command -v jcmd >/dev/null 2>&1; then '
                 'PID=$(jcmd | grep -v jcmd | cut -d" " -f1); '
                 'jcmd $PID Thread.print; '
                 'elif command -v jstack >/dev/null 2>&1; then '
                 'PID=$(ps -ef | grep java | grep -v grep | awk \'{print $2}\'); '
                 'jstack $PID; '
                 'else echo "Neither jcmd nor jstack found"; '
                 'fi')
            ]

            logger.info(f"Executing thread dump command in pod {pod_name}, container {container_name}")

            resp = stream(
                self.core_v1_api.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                container=container_name,
                command=exec_command,
                stderr=True,
                stdin=False,
                stdout=True,
                tty=False
            )

            if resp:
                logger.info("Successfully obtained thread dump")
                return resp
            else:
                logger.warning("No output received from thread dump command")
                return "No output received from thread dump command"

        except ApiException as e:
            logger.error(f"Kubernetes API error in get_thread_dump: {str(e)}")
            raise Exception(f"Kubernetes API error: {e}")
        except ValueError as e:
            logger.error(f"Value error in get_thread_dump: {str(e)}")
            raise Exception(f"Value error: {e}")
        except Exception as e:
            logger.error(f"Unexpected error in get_thread_dump: {str(e)}")
            raise Exception(f"Unexpected error while getting thread dump: {e}")
