//
//  Observable.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//

import Foundation


class Observable<T> {

    var value: T {
        didSet {
            listener?(value)
        }
    }

    private var listener: ((T) -> Void)?

    init(_ value: T) {
        self.value = value
    }

    func bind(_ closure: @escaping (T) -> Void) {
        closure(value)
        listener = closure
    }
}

