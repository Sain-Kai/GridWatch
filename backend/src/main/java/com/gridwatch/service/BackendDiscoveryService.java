package com.gridwatch.service;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Tiny LAN discovery responder so the ESP8266 does not need a hard-coded
 * laptop IP. The gateway broadcasts GRIDWATCH_DISCOVER_V1 and we reply to
 * the sender with the backend port. The sender IP is therefore the laptop
 * address to use for HTTP.
 */
@Service
public class BackendDiscoveryService {
    private static final String DISCOVERY_REQUEST = "GRIDWATCH_DISCOVER_V1";
    private static final String DISCOVERY_RESPONSE_PREFIX = "GRIDWATCH_BACKEND_V1|";

    @Value("${gridwatch.discovery-port:30303}")
    private int discoveryPort;

    @Value("${server.port:8080}")
    private int backendPort;

    private final AtomicBoolean running = new AtomicBoolean(false);
    private DatagramSocket socket;
    private Thread worker;

    @PostConstruct
    public void start() {
        try {
            socket = new DatagramSocket(discoveryPort, InetAddress.getByName("0.0.0.0"));
            socket.setBroadcast(true);
            running.set(true);
            worker = new Thread(this::runLoop, "gridwatch-discovery");
            worker.setDaemon(true);
            worker.start();
            System.out.println("[Discovery] UDP backend discovery listening on port " + discoveryPort);
        } catch (Exception e) {
            System.err.println("[Discovery] Unable to start UDP discovery responder: " + e.getMessage());
        }
    }

    private void runLoop() {
        byte[] buf = new byte[128];
        while (running.get()) {
            try {
                DatagramPacket request = new DatagramPacket(buf, buf.length);
                socket.receive(request);
                String text = new String(request.getData(), request.getOffset(), request.getLength(), StandardCharsets.UTF_8).trim();
                if (!DISCOVERY_REQUEST.equals(text)) continue;
                byte[] responseBytes = (DISCOVERY_RESPONSE_PREFIX + backendPort).getBytes(StandardCharsets.UTF_8);
                DatagramPacket response = new DatagramPacket(
                        responseBytes, responseBytes.length, request.getAddress(), request.getPort());
                socket.send(response);
                System.out.println("[Discovery] Replied to " + request.getAddress().getHostAddress() + ":" + request.getPort());
            } catch (Exception e) {
                if (running.get()) System.err.println("[Discovery] receive/send error: " + e.getMessage());
            }
        }
    }

    @PreDestroy
    public void stop() {
        running.set(false);
        if (socket != null) socket.close();
        if (worker != null) worker.interrupt();
    }
}
