

# Quick Start 

Since our semantics will be testing `Lua 5.1`, build from the following [source](https://www.lua.org/ftp/lua-5.1.5.tar.gz$0). In a directory of your choice, untar and run their Makefile:

```bash
tar zxf lua-5.1.5.tar
cd lua-5.1.5
make macosx
```


# Building for MacOS

If you have `nmap` installed, one of its dependencies will be the most updated version of `Lua`, which is not backwards compatible with some of the tests for `Lua 5.1` (example, `/tests/echo.lua`). In that case, to run the tests in this repository, you will need to point `lua` to your 5.1 binary:

```bash
echo 'export PATH="/path/to/your/binary/lua:$PATH"' >> ~/.zshrc
source ~/.zshrc
```