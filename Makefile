# Makefile for media_listener (Objective-C)

CC = clang
TARGET = media_listener
SOURCES = main.m
FRAMEWORKS = -framework Foundation -F/System/Library/PrivateFrameworks -framework MediaRemote
CFLAGS = -fobjc-arc -I./headers
LDFLAGS = $(FRAMEWORKS)

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) $(LDFLAGS) -o $(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf $(TARGET).dSYM

run: $(TARGET)
	./$(TARGET)

.PHONY: all clean run
