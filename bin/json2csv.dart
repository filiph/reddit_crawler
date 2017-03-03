import 'dart:convert';
import 'dart:io';

import 'package:reddit_crawl/json2csv.dart';

void main(List<String> args) {
  if (args.length != 1) {
    print("Please provide path to input JSON file, and nothing else, "
        "as arguments.");
    exitCode = 2;
    return;
  }

  final file = new File(args.single);

  final content = file.readAsStringSync();
  final List<Map<String, Object>> json = JSON.decode(content);
  redditJson2tsv(json).forEach(print);
}
