"""
Setup script for SnakeBridge Python adapter.
"""

from setuptools import setup, find_packages

setup(
    name="snakebridge-adapter",
    version="0.1.0",
    description="SnakeBridge Python adapter for Snakepit",
    author="nshkrdotcom",
    packages=find_packages(),
    install_requires=[
        "grpcio>=1.59.0",
        "protobuf>=4.25.0",
    ],
    python_requires=">=3.8",
)
