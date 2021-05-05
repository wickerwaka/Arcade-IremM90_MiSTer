#pragma once
#include <queue>
#include "verilated_heavy.h"


#ifndef _MSC_VER
#else
#define WIN32
#endif


struct SimBus_DownloadChunk {
public:
	std::string file;
	int index;
	
	SimBus_DownloadChunk() {
		file = "";
		index = -1;
	}

	SimBus_DownloadChunk(std::string file, int index) {
		this->file = std::string(file);
		this->index = index;
	}
};

struct SimBus {
public:

	IData* ioctl_addr;
	CData* ioctl_index;
	CData* ioctl_wait;
	CData* ioctl_download;
	CData* ioctl_upload;
	CData* ioctl_wr;
	CData* ioctl_dout;
	CData* ioctl_din;

	void BeforeEval(void);
	void AfterEval(void);
	void SimBus::QueueDownload(std::string file, int index);

	SimBus::SimBus(DebugConsole c);
	SimBus::~SimBus();

private:
	std::queue<SimBus_DownloadChunk> downloadQueue;
	SimBus_DownloadChunk currentDownload;
	void SetDownload(std::string file, int index);
};
