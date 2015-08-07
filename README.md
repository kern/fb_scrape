# fb_scrape

A simple scraper for Facebook Groups.

## Requirements

* Ruby 2.x.x
* A Facebook Graph API access token with the `user_groups` permission

## Usage

There are two steps to scraping posts. First, every original post's ID is gathered off the group's feed. Second, each post and all of its comments/likes are fetched in parallel and assembled into a single CSV.

You'll need to export your Facebook Graph API access token as an environment variable. You can retrieve an access token with the `user_groups` permission from the [Graph API Explorer](https://developers.facebook.com/tools/explorer/).

    $ export ACCESS_TOKEN=[ACCESS_TOKEN_GOES_HERE]

To get every original post ID in a group whose ID is `GROUP_ID`:

    $ ruby fb_scrape.rb post_ids GROUP_ID

The IDs will be fetched in large chunks and printed to `STDOUT`, one per line. You can write the IDs to a file for safe keeping:

    $ ruby fb_scrape.rb post_ids GROUP_ID > ids.txt

Next we fetch the posts/comments/likes in parallel. Post IDs are accepted via `STDIN` and a CSV is printed to `STDOUT` making it easy to use pipes:

    $ cat ids.txt | ruby fb_scrape.rb fetch > scraped_data.csv

You can fetch posts from multiple groups simultaneously and they will be tagged
appropriately. If you don't care about saving the post IDs, you can chain both commands together for extra Unix-y goodness:

    $ ruby fb_scrape.rb post_ids GROUP_ID | ruby fb_scrap.rb fetch > scraped_data.csv

The CSV contains all of the scraped data in a consistent format. Data is written incrementally and failed requests (usually due to rate limiting) will be retried every 5 minutes. For very large groups, the CSV will be too big for Excel or other GUI programs to manipulate, so consider importing it into [Google BigQuery](https://cloud.google.com/bigquery/) or R.

## Filtering

If you'd like to filter data from the dataset, you can do so by piping into the `filter` command:

    $ cat scraped_data.csv | ruby fb_scrape.rb filter group_name "Hackathon Hackers" > hh_data.csv

The first argument is the field to use in the dataset for filtering. The second argument is a regular expression that is compared to the field's value for each row, and if matched, adds the row to the output dataset (printed to `STDOUT`).

## Precautions

This scraper will make a hell of a lot of requests using your access token. Be wary that Facebook will inevitably rate limit you, but this is temporary and resets within an hour. If the fetcher detects rate limiting, it will automatically retry the request in 5 minutes.

If a user has blocked you, you will not be able to retrieve their posts and an error will be printed. These are safe to ignore.

Please use this software for good, not evil.

## License

[BSD 3-Clause](https://github.com/kern/fb_scrape/blob/master/LICENSE)
