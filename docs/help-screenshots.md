# Help page screenshots

The images in `app/assets/images/help` are actual Firefox screenshots of the
application. They use fictional accounts with `example.com` email addresses.
The capture runs in the test environment and rolls its database changes back;
it does not send external email or access production.

With the local development services and Selenium running, rebuild the stylesheet
and run the capture explicitly:

```sh
docker compose exec -T web bundle exec rails tailwindcss:build
docker compose exec -T web bundle exec rails test script/capture_help_screenshots.rb
```

The capture walks through sending an invitation, requesting and accepting a
friendship, creating a list, adding items, and filling out a purchase form.
It saves screenshots directly from Selenium elements, without image generation
or subsequent editing. The script lives outside the normal test directories so
ordinary test runs do not overwrite the committed images.

Review each image after capture, including the sample names and addresses. Keep
the help page's image dimensions in sync if a layout change alters their sizes.
Commit refreshed images with any corresponding documentation changes. Rails
includes them in its normal asset build.
