'use strict';

var fs = require('fs');
var path = require('path');

var dbm;
var type;
var seed;
var Promise;

exports.setup = function (options, seedLink) {
  dbm = options.dbmigrate;
  type = dbm.dataType;
  seed = seedLink;
  Promise = options.Promise;
};

// First migration: load the `data_pipeline` DB baseline (public + pipeline schemas;
// bulk_tree_upload = the capture-upload staging table the consumer writes to),
// captured schema-only from the online dev data_pipeline database and sanitized.
exports.up = function (db) {
  var filePath = path.join(
    __dirname,
    'sqls',
    '20260710000000-baseline-data-pipeline-schema-up.sql',
  );
  return new Promise(function (resolve, reject) {
    fs.readFile(filePath, { encoding: 'utf-8' }, function (err, data) {
      if (err) return reject(err);
      resolve(data);
    });
  }).then(function (data) {
    return db.runSql(data);
  });
};

exports.down = function (db) {
  return db.runSql(
    'DROP SCHEMA IF EXISTS pipeline CASCADE; DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;',
  );
};

exports._meta = { version: 1 };
