# RunAs Attached (Local) - 32bit / 64bit

RunAsAttached is a program to locally run a new terminal as another user without spawning a new console window.

# Youtube Video (Click on bellow image)

[![Demo](http://i3.ytimg.com/vi/6hY6G5OtTWA/maxresdefault.jpg)](https://youtu.be/6hY6G5OtTWA)

# Important Notice

This version of RunAsAttached can be used locally only. If you wish to have a version compatible with programs like Netcat check this repository: https://github.com/DarkCoderSc/run-as-attached-networked

The reason is pretty simple, even if it wasn't something absolutely necessary, I decided to make all operation on console window completely synchronized between both Stdin and Stdout/Stderr threads.

I was forced to kinda re-code the function `ReadLn` to do so. Since `ReadLn` is a blocking function, you can't protect access to console buffer using critical sections. 

To re-create the behavior of `ReadLn` I used `ReadConsoleInput` API, which reads keyboard events on console Window and prevent software that "hooks" console std(s) to capture user input.

You can however remove the use of `TStdinHandler` thread and just call `ReadLn` and remove every piece of code related to thread synchronization with the risk of having in rare cases strange behaviors. 

It is also a good exercise to learn how to both manage console input by hand and thread synchronization.

# Notes

Just a very minor known issue is related to writing command when a long command is still running and dumping content. It can sometimes break the command you write in few parts without affecting the stability of the program. Anyway it is recommended to wait until a command finish to process until you decide to write and process another command.

I'm working on a way limit that tiny issue.
