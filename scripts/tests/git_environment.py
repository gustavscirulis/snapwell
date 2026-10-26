"""Keep synthetic Git repositories independent of the enclosing real Git hook."""
from contextlib import contextmanager
import os
from unittest.mock import patch


@contextmanager
def git_fixture_environment():
    # Hooks export GIT_DIR, GIT_CONFIG, GIT_INDEX_FILE and other repository-local
    # variables. Keeping them while changing cwd can mutate the caller's repository.
    environment = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1')
    with patch.dict(os.environ, environment, clear=True):
        yield
