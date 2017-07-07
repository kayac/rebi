# Rebi
Deployment tool for Elasticbeanstalk

# Features
  - Switchable  + multiple bextensions folder
  - Support erb in ebextension config files
  - Support env_file for environment variables
  - Multiple deployment
  - Deploy source code along with updating beanstalk options
  - Simple config

## Installation
Or install it yourself as:
```bash
$ gem install rebi
```

## Usage
How to use my plugin.

Create sample config
```bash
$ bundle exec rebi sample > rebi.yml
```

Default config file is `config/rebi.yml` use `-c` to switch
```bash
$ bundle exec rebi deploy development web
```

For more help
```
$ bundle exec rebi --help
```

Use `rebi_env` to get environment variables config in .ebextensions
```yaml
# Ex
# .ebextensions/00-envrionments.config
option_settings:
  - option_name: KEY
    value: <%= rebi_env[KEY] %>
```

## Contributing
Feel free to fork and request a pull, or submit a ticket
https://github.com/khiemns54/rebi/issues

## License
The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
