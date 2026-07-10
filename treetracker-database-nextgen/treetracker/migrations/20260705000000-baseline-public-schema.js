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

// First migration: load the full `public` schema baseline captured from the online
// nextgen dev DB (schema-only, sanitized for driver execution). Subsequent schema
// changes go in later migrations.
exports.up = function (db) {
  var filePath = path.join(
    __dirname,
    'sqls',
    '20260705000000-baseline-public-schema-up.sql',
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
  // Reset the public schema wholesale (baseline is not incrementally reversible).
  return db.runSql('DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;');
};

exports._meta = { version: 1 };
