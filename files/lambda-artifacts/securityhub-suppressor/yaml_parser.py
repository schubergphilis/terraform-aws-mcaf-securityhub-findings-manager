from ctypes import Union
from parser import ParserError

import yaml
from aws_lambda_powertools import Logger
from yamllint import linter
from yamllint.config import YamlLintConfig

logger = Logger()


def get_file_contents(file_name) -> any:
    try:
        file_contents = yaml.load(open(file_name, 'r').read().strip(), Loader=yaml.FullLoader)
    except IOError:
        logger.error(f'Unable to read {file_name}')
        return None
    except (ValueError, ParserError) as error:
        logger.error(f'Unable to parse file {file_name} as yaml, error: {error}')
        return None
    return file_contents


def run_yaml_lint(file_name) -> bool:
    conf = YamlLintConfig('extends: default')
    yaml_linting_result = linter.run(open(file_name), conf)
    success = True
    for line in yaml_linting_result:
        if line.level == 'warning':
            print(f'\tWARNING: {line}')
        if line.level == 'error':
            print(f'\tERROR: {line}')
            success = False
    return success
