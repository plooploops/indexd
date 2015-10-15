import flask
import pytest

import util
import indexd

from indexd.index.blueprint import blueprint as indexd_index_blueprint
from indexd.alias.blueprint import blueprint as indexd_alias_blueprint

from indexd.index.drivers.sqlalchemy import SQLAlchemyIndexDriver
from indexd.alias.sqlite import SQLiteAliasDriver


INDEX_CONFIG = {
    'driver': SQLAlchemyIndexDriver('sqlite:///index.sq3'),
}

ALIAS_CONFIG = {
    'driver': SQLiteAliasDriver,
    'SQLITE3': {
        'host': 'alias.sq3',
    }
}

@util.removes('index.sq3')
@util.removes(ALIAS_CONFIG['SQLITE3']['host'])
def test_flask_blueprint():
    '''
    Tests standing up the server using flask.
    '''
    app = flask.Flask(__name__)

    app.config['INDEX'] = INDEX_CONFIG
    app.config['ALIAS'] = ALIAS_CONFIG

    app.register_blueprint(indexd_index_blueprint)
    app.register_blueprint(indexd_alias_blueprint)

@util.removes(ALIAS_CONFIG['SQLITE3']['host'])
def test_flask_blueprint_missing_index_config():
    '''
    Tests standing up the server using flask without an index config.
    '''
    app = flask.Flask(__name__)

    app.config['ALIAS'] = ALIAS_CONFIG

    with pytest.raises(Exception):
        app.register_blueprint(indexd_index_blueprint)

    app.register_blueprint(indexd_alias_blueprint)

@util.removes(ALIAS_CONFIG['SQLITE3']['host'])
def test_flask_blueprint_invalid_index_config():
    '''
    Tests standing up the server using flask without an index config.
    '''
    app = flask.Flask(__name__)

    app.config['INDEX'] = None
    app.config['ALIAS'] = ALIAS_CONFIG

    with pytest.raises(Exception):
        app.register_blueprint(indexd_index_blueprint)

    app.register_blueprint(indexd_alias_blueprint)

@util.removes('index.sq3')
def test_flask_blueprint_missing_alias_config():
    '''
    Tests standing up the server using flask without an alias config.
    '''
    app = flask.Flask(__name__)

    app.config['INDEX'] = INDEX_CONFIG

    with pytest.raises(Exception):
        app.register_blueprint(indexd_alias_blueprint)

    app.register_blueprint(indexd_index_blueprint)

@util.removes('index.sq3')
def test_flask_blueprint_invalid_alias_config():
    '''
    Tests standing up the server using flask without an alias config.
    '''
    app = flask.Flask(__name__)

    app.config['INDEX'] = INDEX_CONFIG
    app.config['ALIAS'] = None

    with pytest.raises(Exception):
        app.register_blueprint(indexd_alias_blueprint)

    app.register_blueprint(indexd_index_blueprint)
