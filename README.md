# reddit_crawl

A command line tool that uses the Reddit API to track popularity of a keyword.
The tool is currently focused on tracking developer technologies, such as
programming languages, frameworks or IDEs.

## Installation

1. Make sure you have Dart installed and it's in your path.
2. Run `pub global activate reddit_crawl`.

## Example usage

To get data for "dart" for the past 3 months (default), run this: 

```
$ reddit_crawl dart
```

This will fetch the data and it will create 2 sets of files in the current
working directory:

1. output-dart-2018-01-01 (.json and .tsv) with the results of this run
    * This is useful for 'point in time' view and for backup of previous runs.
2. output-dart-all (.json and .tsv) with the results of this run merged with
   whatever was there previously
    * This is your 'tracking' output that you can update with latest Reddit
      buzz as time progresses.
   
The JSON files include all the data received from Reddit API. The TSV file
is useful for copypasting into spreadsheets and includes only a subset of the
data and some helper columns.

### Advanced usage

Run the tool without parameters to get help.

```
$ reddit_crawl
Exactly one argument is requred: a name of a technology.

Additional options:
-v, --verbose    Verbose mode.
    --months     Number of months to crawl in reverse chronological order.
                 (defaults to "3")

    --mobile     Use additional subreddits that specialize in mobile development.
    --web        Use additional subreddits that specialize in web development.
```

To get all mentions of "vim" on major Reddit programming forums, including 
mobile- and web-focused ones, from the past 6 years (6 * 12 = 72 months), use:

```
$ reddit_crawl --months 72 --mobile --web vim 
```

Later, you can just run `reddit_crawl --mobile --web vim` to update your
`output-vim-all` files with the latest submissions.
