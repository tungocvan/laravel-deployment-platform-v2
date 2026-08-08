# Module Contract

Một module hợp lệ phải:

- có `commands/help.sh`
- mọi command executable
- không source module khác trực tiếp nếu không khai báo dependency
- shared logic đặt trong core hoặc public module API
- có docs
- có test
