# Borealis Isolated Postgres Heroku Buildpack

A [Heroku buildpack](https://devcenter.heroku.com/articles/buildpacks) to establish a secure tunnel between a Heroku app and a [Borealis Isolated Postgres](https://elements.heroku.com/addons/borealis-pg) add-on database cluster.

## Usage

Use the [Heroku CLI](https://devcenter.heroku.com/articles/heroku-cli) to add the buildpack to an existing Heroku app so the app can seamlessly connect to an add-on database over a secure tunnel:

```shell
heroku buildpacks:add --index 1 borealis/postgres-tunnel
```

That's it! The buildpack will automatically detect config variables from a Borealis Isolated Postgres add-on and set up a secure tunnel the next time the app is deployed to Heroku. The deployed app can then proceed to connect to the database cluster using the value from the Postgres URL config variable (e.g. `DATABASE_URL`).

## Documentation

For full instructions (including for Docker deploys), see the [Installing the Buildpack](https://devcenter.heroku.com/articles/borealis-pg#installing-the-buildpack) section of the add-on's article on the Heroku Dev Center.
