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

  final queryParameters = {'q': '"in $language" programming nsfw:no'};
  // TODO: use timestamp if we ever hit the 1000 results limit
  //       https://www.reddit.com/wiki/search#wiki_cloudsearch_syntax
  final uri = Uri
      .parse("https://oauth.reddit.com/search")
      .replace(queryParameters: queryParameters);
  final firstJson = await _getListing(client, uri);
  Map jsonObject = JSON.decode(firstJson);

  if (jsonObject['data'] == null) {
    print("ERROR");
    print(jsonEnconder.convert(jsonObject));
    exitCode = 2;
    client.close();
    return;
  }

  final List<Map<String, Object>> entities = jsonObject['data']['children'];

  String afterToken = jsonObject['data']['after'];

  while (afterToken != null) {
    await new Future.delayed(new Duration(seconds: _random.nextInt(10)));
    queryParameters['after'] = afterToken;
    final nextUri = uri.replace(queryParameters: queryParameters);
    final nextJson = await _getListing(client, nextUri);
    jsonObject = JSON.decode(nextJson);
    if (jsonObject['data'] == null) {
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
  }

  client.close();

  final output = jsonEnconder.convert(entities);

  final now = new DateTime.now();

  final file =
      new File("output-$language-${now.year}-${now.month}-${now.day}.json");
  await file.writeAsString(output);
  print("Output written to $file");

  final tsvFile = new File(path.withoutExtension(file.path) + ".tsv");
  final tsvOutput = redditJson2tsv(entities);

  await tsvFile.writeAsString(tsvOutput.join('\n'));
  print("TSV written to $tsvFile");
}

/// curl -u ***REMOVED***:***REMOVED*** --data "grant_type=client_credentials" -A "filiph UA" https://www.reddit.com/api/v1/access_token
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

Future<bool> _auth(http.Client client) async {
  final uri = Uri.parse(r"https://www.reddit.com/api/v1/access_token");
  final request = new http.Request("post", uri);
  request.headers[HttpHeaders.USER_AGENT] = userAgent;
  request.headers[HttpHeaders.AUTHORIZATION] =
      'Basic ${encodeAuth(clientId, appSecret)}';
  request.bodyFields = {'grant_type': 'client_credentials'};
  final response = await client.send(request);
  final json = await response.stream.bytesToString();
  final jsonObject = JSON.decode(json);
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
  final response = await client.send(request);
  final json = await response.stream.bytesToString();
  return json;
}
