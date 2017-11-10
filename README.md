# Rebi
Deployment tool for Elasticbeanstalk

# Features
  - Switchable  + multiple ebextensions folder
  - Support erb in ebextension config files
  - Support env_file for environment variables
  - Multiple deployment
  - Deploy source code along with updating beanstalk options
  - Simple config
  - Simple ssh

## Installation
Or install it yourself as:
```bash
$ gem install rebi
```

## Usage
How to use my plugin.

### AWS authentication
Rebi uses environment variables to get aws credentials
To set environment variables use `export` or `.env` file
```bash
# Use access key
export AWS_ACCESS_KEY_ID=xxxxx
export AWS_SECRET_ACCESS_KEY=xxxxxx
```
Or
```bash
# Use profile
export AWS_PROFILE=xxxxx
```

Refer http://docs.aws.amazon.com/sdkforruby/api/Aws/ElasticBeanstalk/Client.html for other settings

### Yaml config
Default config file is `config/rebi.yml` use `-c` to switch
```yaml
app_name: app-name
stages:
  development:
    web:
      name: web01
      env_file: .env.development
      ebextensions: "web-ebextensions"
```

For other configs( key_name, instance_type, instance_num, service_role,...), please refer sample config
```bash
$ bundle exec rebi sample > rebi.yml
```

### Deploy
```bash
# Single deploy
$ bundle exec rebi deploy development web
```

```bash
# Multiple deploy (if development has more than one environments)
$ bundle exec rebi deploy development
```

### Ssh
```bash
$ bundle exec rebi ssh development web
```


### Get envronment variables and status
```bash
# Running envronment variables
$ bundle exec rebi get_env development
# envronment variables for config
$ bundle exec rebi get_env development --from-config
# Status
$ bundle exec rebi status development
```

###For more help
```bash
$ bundle exec rebi --help
```

### ERB in ebextensions config
Use `rebi.env` to get environment variables config in .ebextensions
```yaml
# Ex
# .ebextensions/00-envrionments.config
option_settings:
  - option_name: KEY
    value: <%= rebi.env[KEY] %>
```

Use `rebi.opts` or `rebi.options` to get options config in .ebextensions
```yaml
# Ex
# .ebextensions/00-envrionments.config
option_settings:
  - option_name: KEY
    value: <%= rebi.options[KEY] %>
```

## Contributing
Feel free to fork and request a pull, or submit a ticket
https://github.com/khiemns54/rebi/issues

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
