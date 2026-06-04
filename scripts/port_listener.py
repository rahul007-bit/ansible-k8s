import socket
import sys
import threading
import time

def listen_tcp(port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        s.listen(5)
        s.settimeout(1)
        while True:
            try:
                c, _ = s.accept()
                c.close()
            except socket.timeout:
                pass
    except Exception as e:
        print(f"TCP bind failed on {port}: {e}")

def listen_udp(port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('0.0.0.0', port))
        s.settimeout(1)
        while True:
            try:
                s.recvfrom(1024)
            except socket.timeout:
                pass
    except Exception as e:
        print(f"UDP bind failed on {port}: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python port_listener.py <timeout_seconds> <protocol:port> ...")
        sys.exit(1)
    
    timeout = int(sys.argv[1])
    ports = sys.argv[2:]
    
    for p in ports:
        proto, port_str = p.split(':')
        # handle ranges
        if '-' in port_str:
            start_port, end_port = map(int, port_str.split('-'))
            # limit range to prevent too many threads/sockets if it's nodeports
            # actually we don't need to listen on thousands of NodePorts, just one or two from the range is enough for testing
            if end_port - start_port > 10:
                end_port = start_port + 1 # just test first 2 ports of large ranges
            port_list = range(start_port, end_port + 1)
        else:
            port_list = [int(port_str)]
            
        for port in port_list:
            if proto.lower() == 'tcp':
                t = threading.Thread(target=listen_tcp, args=(port,), daemon=True)
                t.start()
            elif proto.lower() == 'udp':
                t = threading.Thread(target=listen_udp, args=(port,), daemon=True)
                t.start()
            
    time.sleep(timeout)
