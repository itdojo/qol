## Internet Check & WiFi Check Scripts

- [ ] Add `internet_check.sh` and `wifi_check.sh` to `~/scripts`.  Mark both executable.

- [ ] Edit `~/.zshrc` or `~/.bashrc`, adding:

> `echo $SHELL` if you don't which shell you are using.

    ```shell
    printf "\n"
    ~/scripts/wifi_check.sh
    ~/scripts/internet_check.sh
    printf "\n"
    ```

<img src=assets/internet_ssid_check.jpg width=100%>
