// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/lang.'string;
import ballerina/test;
import ballerina/io;

string MESSAGE_KEY = "TEST-KEY";
const string INVALID_URL = "127.0.0.1.1:9099";
const string INCORRECT_KAFKA_URL = "localhost:9099";

@test:Config{}
function producerInitTest() returns error? {
    ProducerConfiguration producerConfiguration1 = {
        clientId: "test-producer-01",
        acks: ACKS_ALL,
        maxBlock: 6,
        requestTimeout: 2,
        retryCount: 3
    };
    ProducerConfiguration producerConfiguration2 = {
        clientId: "test-producer-02",
        acks: ACKS_ALL,
        maxBlock: 6,
        requestTimeout: 2,
        retryCount: 3,
        transactionalId: "prod-id-1",
        enableIdempotence: true
    };
    ProducerConfiguration producerConfiguration3 = {
        clientId: "test-producer-03",
        acks: ACKS_ALL,
        maxBlock: 6,
        requestTimeout: 2,
        retryCount: 3,
        transactionalId: "prod-id-2"
    };
    Producer result1 = check new (DEFAULT_URL, producerConfiguration1);
    Producer result2 = check new (DEFAULT_URL, producerConfiguration2);
    check result1->close();
    check result2->close();

    Producer|Error result3 = new (DEFAULT_URL, producerConfiguration3);
    if (result3 is Error) {
        string expectedErr = "configuration enableIdempotence must be set to true to enable " +
            "transactional producer";
         test:assertEquals(result3.message(), expectedErr);
    } else {
        test:assertFail(msg = "Expected an error");
    }

    Producer|Error result4 = new (INVALID_URL, producerConfiguration1);
    if (result4 is Error) {
        string expectedErr = "Failed to initialize the producer: Failed to construct kafka producer";
        test:assertEquals(result4.message(), expectedErr);
    } else {
        test:assertFail(msg = "Expected an error");
    }
}

@test:Config {}
function producerSendStringTest() returns error? {
    string topic = "send-string-test-topic";
    Producer stringProducer = check new (DEFAULT_URL, producerConfiguration);
    string message = "Hello, Ballerina";
    Error? result = stringProducer->send({ topic: topic, value: message.toBytes() });
    test:assertFalse(result is error, result is error ? result.toString() : result.toString());
    result = stringProducer->send({ topic: topic, value: message.toBytes(), key: MESSAGE_KEY.toBytes() });
    check stringProducer->close();

    ConsumerConfiguration consumerConfiguration = {
        topics: [topic],
        offsetReset: OFFSET_RESET_EARLIEST,
        groupId: "producer-send-string-test-group",
        clientId: "test-producer-04"
    };
    Consumer consumer = check new (DEFAULT_URL, consumerConfiguration);
    ConsumerRecord[] consumerRecords = check consumer->poll(3);
    test:assertEquals(consumerRecords.length(), 2);
    byte[] messageValue = consumerRecords[0].value;
    string messageConverted = check 'string:fromBytes(messageValue);
    test:assertEquals(messageConverted, TEST_MESSAGE);
    check consumer->close();
}

@test:Config {}
function producerKeyTypeMismatchErrorTest() returns error? {
    string topic = "key-type-mismatch-error-test-topic";
    Producer producer = check new (DEFAULT_URL, producerConfiguration);
    string message = "Hello, Ballerina";
    error? result = trap sendByteArrayValues(producer, message.toBytes(), topic, MESSAGE_KEY, 0, (), SER_BYTE_ARRAY);
    if (result is error) {
        string expectedErr = "Invalid type found for Kafka key. Expected key type: 'byte[]'.";
        test:assertEquals(result.message(), expectedErr);
    } else {
        test:assertFail(msg = "Expected an error");
    }
    check producer->close();
}

@test:Config {
    dependsOn: [producerSendStringTest]
}
function producerCloseTest() returns error? {
    string topic = "producer-close-test-topic";
    Producer closeTestProducer = check new (DEFAULT_URL, producerConfiguration);
    string message = "Test Message";
    Error? result = closeTestProducer->send({ topic: topic, value: message.toBytes() });
    test:assertFalse(result is error, result is error ? result.toString() : result.toString());
    result = closeTestProducer->close();
    test:assertFalse(result is error, result is error ? result.toString() : result.toString());
    result = closeTestProducer->send({ topic: topic, value: message.toBytes() });
    test:assertTrue(result is error);
    error receivedErr = <error>result;
    string expectedErr = "Failed to send data to Kafka server: Cannot perform operation after producer has been closed";
    test:assertEquals(receivedErr.message(), expectedErr);
}

@test:Config {}
function producerFlushTest() returns error? {
    string topic = "producer-flush-test-topic";
    Producer flushTestProducer = check new (DEFAULT_URL, producerConfiguration);
    check flushTestProducer->send({ topic: topic, value: TEST_MESSAGE.toBytes() });
    check flushTestProducer->'flush();
    check flushTestProducer->close();

    ConsumerConfiguration consumerConfiguration = {
        topics: [topic],
        offsetReset: OFFSET_RESET_EARLIEST,
        groupId: "producer-flush-test-group",
        clientId: "test-producer-05"
    };
    Consumer consumer = check new (DEFAULT_URL, consumerConfiguration);
    ConsumerRecord[] consumerRecords = check consumer->poll(3);
    test:assertEquals('string:fromBytes(consumerRecords[0].value), TEST_MESSAGE);
    check consumer->close();
}

@test:Config {}
function producerGetTopicPartitionsTest() returns error? {
    string topic = "get-topic-partitions-test-topic";
    Producer topicPartitionTestProducer = check new (DEFAULT_URL, producerConfiguration);
    TopicPartition[] topicPartitions = check topicPartitionTestProducer->getTopicPartitions(topic);
    test:assertEquals(topicPartitions[0].partition, 0, "Expected: 0. Received: " + topicPartitions[0].partition.toString());
    check topicPartitionTestProducer->close();
}

@test:Config {}
function producerGetTopicPartitionsErrorTest() returns error? {
    string topic = "get-topic-partitions-error-test-topic";
    Producer topicPartitionTestProducer = check new (INCORRECT_KAFKA_URL, producerConfiguration);
    TopicPartition[]|Error result = topicPartitionTestProducer->getTopicPartitions(topic);
    if (result is error) {
        string expectedErr = "Failed to fetch partitions from the producer Topic " +
                                topic + " not present in metadata after ";
        test:assertEquals(result.message().substring(0, expectedErr.length()), expectedErr);
    } else {
        test:assertFail(msg = "Expected an error");
    }
    check topicPartitionTestProducer->close();
}

@test:Config {}
function transactionalProducerTest() returns error? {
    string topic = "transactional-producer-test-topic";
    ProducerConfiguration producerConfigs = {
        clientId: "test-producer-06",
        acks: "all",
        retryCount: 3,
        enableIdempotence: true,
        transactionalId: "test-transactional-id"
    };
    Producer transactionalProducer = check new (DEFAULT_URL, producerConfigs);
    transaction {
        check transactionalProducer->send({
            topic: topic,
            value: TEST_MESSAGE.toBytes(),
            partition: 0
        });
        var commitResult = commit;
        if (commitResult is ()) {
            io:println("Commit successful");
        } else {
            test:assertFail(msg = "Commit Failed");
        }
    }
    check transactionalProducer->close();

    ConsumerConfiguration consumerConfiguration = {
        topics: [topic],
        offsetReset: OFFSET_RESET_EARLIEST,
        groupId: "producer-transactional-test-group",
        clientId: "test-consumer-38"
    };
    Consumer consumer = check new (DEFAULT_URL, consumerConfiguration);
    ConsumerRecord[] consumerRecords = check consumer->poll(5);
    test:assertEquals(consumerRecords.length(), 1, "Expected: 1. Received: " + consumerRecords.length().toString());
    check consumer->close();
}

@test:Config{}
function saslProducerTest() returns error? {
    string topic = "sasl-producer-test-topic";
    AuthenticationConfiguration authConfig = {
        mechanism: AUTH_SASL_PLAIN,
        username: SASL_USER,
        password: SASL_PASSWORD
    };

    ProducerConfiguration producerConfigs = {
        clientId: "test-producer-07",
        acks: ACKS_ALL,
        maxBlock: 6,
        requestTimeout: 2,
        retryCount: 3,
        auth: authConfig,
        securityProtocol: PROTOCOL_SASL_PLAINTEXT
    };

    Producer kafkaProducer = check new (SASL_URL, producerConfigs);

    Error? result = kafkaProducer->send({topic: topic, value: TEST_MESSAGE.toBytes() });
    test:assertFalse(result is error, result is error ? result.toString() : result.toString());
    check kafkaProducer->close();

    ConsumerConfiguration consumerConfiguration = {
        topics: [topic],
        offsetReset: OFFSET_RESET_EARLIEST,
        groupId: "sasl-producer-test-group",
        clientId: "test-consumer-39"
    };
    Consumer consumer = check new (DEFAULT_URL, consumerConfiguration);
    ConsumerRecord[] consumerRecords = check consumer->poll(5);
    test:assertEquals(consumerRecords.length(), 1, "Expected: 1. Received: " + consumerRecords.length().toString());
    check consumer->close();
}

@test:Config{}
function saslProducerIncorrectCredentialsTest() returns error? {
    string topic = "sasl-producer-incorrect-credentials-test-topic";
    AuthenticationConfiguration authConfig = {
        mechanism: AUTH_SASL_PLAIN,
        username: SASL_USER,
        password: SASL_INCORRECT_PASSWORD
    };

    ProducerConfiguration producerConfigs = {
        clientId: "test-producer-08",
        acks: ACKS_ALL,
        maxBlock: 6,
        requestTimeout: 2,
        retryCount: 3,
        auth: authConfig,
        securityProtocol: PROTOCOL_SASL_PLAINTEXT
    };

    Producer kafkaProducer = check new (SASL_URL, producerConfigs);

    Error? result = kafkaProducer->send({topic: topic, value: TEST_MESSAGE.toBytes() });
    if result is Error {
        string errorMsg = "Failed to send data to Kafka server: Authentication failed: Invalid username or password";
        test:assertEquals(result.message(), errorMsg);
    } else {
        test:assertFail(msg = "Expected an error");
    }
    check kafkaProducer->close();
}
