.PHONY: build app textures run install demo clean

build:
	bash Scripts/build.sh

app:
	bash Scripts/build.sh --app

textures:
	python3 Scripts/banner_math.py --out Resources

run: build
	./build/NotchBanner

install:
	bash Scripts/install.sh

demo: build
	./build/NotchBanner --record-demo assets/demo.mp4

clean:
	rm -rf build dist
