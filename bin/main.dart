// Copyright (c) 2017, Filip Hracek. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:reddit_crawl/config.dart' show clientId, appSecret;
import 'package:reddit_crawl/json2csv.dart';

Future<Null> main(List<String> arguments) async {
  if (arguments.length != 1) {
    print("Exactly one argument is requred: a programming language name.");
    exitCode = 2;
    return;
  }

  final language = arguments.single.trim();

  final client = new http.Client();

  while (!await _auth(client)) {
    print("ERROR");
    await new Future.delayed(new Duration(seconds: _random.nextInt(10)));
  }

  //  final subreddits = await findSubreddits("programming", client);
  //  print(JSON.encode(subreddits));
  //  client.close();
  //  return;

  final now = new DateTime.now();
  const int monthCount = 72;

  final List<Map<String, Object>> entities = [];

  for (int i = 0; i < monthCount; i++) {
    final to = new DateTime(now.year, now.month - i);
    final from = new DateTime(to.year, to.month - 1);

    print("Getting for ${from.year}-${from.month}.");
    await getFullListing(language, from, to, client, entities);
  }

  client.close();

  print("\nFound ${entities.length} articles.");

  final output = jsonEnconder.convert(entities);

  final file = new File(
      "output-$language-${now.toIso8601String().substring(0, 10)}.json");
  await file.writeAsString(output);
  print("Output written to $file");

  final tsvFile = new File(path.withoutExtension(file.path) + ".tsv");
  final tsvOutput = submissionsJson2tsv(entities);

  await tsvFile.writeAsString(tsvOutput.join('\n'));
  print("TSV written to $tsvFile");
}

/// Gets the listing even if it's multi-page.
///
/// https://www.reddit.com/dev/api/#GET_subreddits_search
Future<List<Map<String, Object>>> findSubreddits(
    String query, http.Client client) async {
  final queryParameters = {
    'q': query,
  };

  final List<Map<String, Object>> entities = [];

  String afterToken;

  // ignore: literal_only_boolean_expressions
  while (true) {
    await new Future.delayed(new Duration(seconds: _random.nextInt(10)));
    if (afterToken != null) {
      queryParameters['after'] = afterToken;
    }
    final uri = Uri
        .parse("https://oauth.reddit.com/subreddits/search")
        .replace(queryParameters: queryParameters);
    final nextJson = await _getListing(client, uri);
    Map<String, dynamic> jsonObject;
    try {
      jsonObject = JSON.decode(nextJson);
    } on FormatException {
      print("\nERROR: response isn't parseable JSON");
    }
    if (jsonObject == null || jsonObject['data'] == null) {
      print("\nERROR?");
      print(jsonEnconder.convert(jsonObject));
      await new Future.delayed(new Duration(seconds: _random.nextInt(30)));
      if (!await _auth(client)) {
        print("ERROR: couldn't authenticate");
      }
      await new Future.delayed(new Duration(seconds: _random.nextInt(30)));
      continue;
    }
    entities.addAll(jsonObject['data']['children']);
    stdout.write(".");
    afterToken = jsonObject['data']['after'];
    if (afterToken == null) break;
  }

  return entities;
}

/// List of top programming and SW development subreddits that are generic
/// or didactic in nature.
///
/// Together, these 12 subreddits have 1M+ subscribers (cumulative).
const List<String> subreddits = const [
  // Generic
  "programming",
  "WatchPeopleCode",
  "AskProgramming",
  "programmingtools",
  "programmerchat",
  // Didactic
  "learnprogramming",
  "dailyprogrammer",
  "tinycode",
  "programmingchallenges",
  "code",
  "ProgrammingBuddies",
  "programming_tutorials"
];

/// The url part that creates a 'temporary multireddit' (like `pics+aww` in
/// http://www.reddit.com/r/pics+aww).
final String subredditsInUrl = subreddits.join('+');

/// Gets the listing even if it's multi-page, and adds it to [entities].
Future getFullListing(String language, DateTime from, DateTime to,
    http.Client client, List<Map<String, Object>> entities) async {
  // https://www.reddit.com/wiki/search#wiki_cloudsearch_syntax
  final cloudSearchQuery = "(and "
      "(field text '$language') "
      "timestamp:${from.millisecondsSinceEpoch ~/ 1000}"
      "..${to.millisecondsSinceEpoch ~/ 1000}"
      ")";

  print("query: $cloudSearchQuery");

  final queryParameters = {
    'q': cloudSearchQuery,
    't': 'all',
    // restrict_sr must be 'on' for temporary multireddits
    // https://www.reddit.com/r/help/comments/3muaic/how_to_use_cloudsearch_for_searching_multiple/cvi5yrn/
    'restrict_sr': 'on',
    'syntax': 'cloudsearch',
  };

  String afterToken;

  // ignore: literal_only_boolean_expressions
  while (true) {
    await new Future.delayed(new Duration(seconds: _random.nextInt(10)));
    if (afterToken != null) {
      queryParameters['after'] = afterToken;
    }
    final uri = Uri
        .parse("https://oauth.reddit.com/r/$subredditsInUrl/search")
        .replace(queryParameters: queryParameters);
    print(uri);
    final nextJson = await _getListing(client, uri);
    Map<String, dynamic> jsonObject;
    try {
      jsonObject = JSON.decode(nextJson);
    } on FormatException {
      print("\nERROR: response isn't parseable JSON");
    }
    if (jsonObject == null || jsonObject['data'] == null) {
      print("\nERROR?");
      print(jsonEnconder.convert(jsonObject));
      await new Future.delayed(new Duration(seconds: _random.nextInt(30)));
      if (!await _auth(client)) {
        print("ERROR: couldn't authenticate");
      }
      await new Future.delayed(new Duration(seconds: _random.nextInt(30)));
      continue;
    }
    entities.addAll(jsonObject['data']['children']);
    stdout.write(".");
    afterToken = jsonObject['data']['after'];
    if (afterToken == null) break;
  }
}

var accessToken;

final jsonEnconder = new JsonEncoder.withIndent('  ');

final userAgent = "Dart watcher tool (github.com/filiph)";

final _random = new Random();

String encodeAuth(String username, String password) {
  final both = "$username:$password";
  final bytes = UTF8.encode(both);
  final base64 = BASE64.encode(bytes);
  return base64;
}

/// Updates [accessToken] by calling the Reddit OAuth API.
///
/// Equivalent to:
///
///     curl -u app_id:secret \
///         --data "grant_type=client_credentials" \
///         -A "some UA other than default" \
///         https://www.reddit.com/api/v1/access_token
Future<bool> _auth(http.Client client) async {
  final uri = Uri.parse(r"https://www.reddit.com/api/v1/access_token");
  final request = new http.Request("post", uri);
  request.headers[HttpHeaders.USER_AGENT] = userAgent;
  request.headers[HttpHeaders.AUTHORIZATION] =
      'Basic ${encodeAuth(clientId, appSecret)}';
  request.bodyFields = {'grant_type': 'client_credentials'};
  final response = await client.send(request);
  final json = await response.stream.bytesToString();
  Map jsonObject;
  try {
    jsonObject = JSON.decode(json);
  } on FormatException {
    print("ERROR: non-JSON response in auth");
  }
  if (jsonObject == null) {
    return false;
  }
  final newToken = jsonObject['access_token'];
  if (newToken == null) {
    print(jsonEnconder.convert(jsonObject));
    return false;
  }
  accessToken = newToken;
  return true;
}

Future<String> _getListing(http.Client client, Uri uri) async {
  final request = new http.Request("get", uri);
  request.headers[HttpHeaders.USER_AGENT] = userAgent;
  request.headers[HttpHeaders.AUTHORIZATION] = "bearer $accessToken";
  // TODO: catch SocketException
  final response = await client.send(request);
  final json = await response.stream.bytesToString();
  return json;
}
